using System;
using System.Buffers.Binary;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;
using NAudio.Dsp;
using NAudio.Wave;

namespace MusicFetcher
{
    internal readonly record struct SpectrumSnapshot(
        float[] Levels,
        long UpdatedAtMs,
        bool Available,
        string? Error,
        double Rms,
        long SampleFrames,
        string Format,
        string CaptureMode,
        int TargetProcessId
    );

    internal sealed class SpectrumAnalyzer : IDisposable, IMMNotificationClient
    {
        private static readonly Guid IeeeFloatSubFormat = new(
            "00000003-0000-0010-8000-00AA00389B71"
        );
        private const int FftLength = 2048;
        private const int FftExponent = 11;
        private const int BandCount = 32;
        private const int AnalysisHopSamples = 1024;
        private const long AnalysisIntervalMs = 33;
        private const long ClientIdleTimeoutMs = 1200;

        private readonly object _sync = new();
        private readonly float[] _ring = new float[FftLength];
        private readonly float[] _window = new float[FftLength];
        private readonly Complex[] _fft = new Complex[FftLength];
        private readonly float[] _levels = new float[BandCount];
        private readonly Timer _idleTimer;
        private readonly SemaphoreSlim _lifecycle = new(1, 1);
        private readonly int[] _startBins = new int[BandCount];
        private readonly int[] _endBins = new int[BandCount];
        private MMDeviceEnumerator? _deviceEnumerator;
        private int _maintenanceQueued;
        private int _maintenanceAgain;
        private int _disposed;
        private int _deviceRevision;
        private long _lastDeviceChangeAt;
        private int _activeDeviceRevision = -1;
        private int _targetRevision;
        private int _activeTargetRevision = -1;
        private int _targetProcessId;
        private string _captureMode = "idle";
        private long _nextRetryAt;
        private int _failureCount;
        private long _nextProcessLookupAt;
        private long _processRetryAt;
        private bool _captureStopped;
        private long _captureStartedAt;

        private int _writeIndex;
        private int _sampleCount;
        private int _samplesSinceAnalysis;
        private int _sampleRate = 48000;
        private int _channels = 2;
        private int _bytesPerSample = 4;
        private bool _isFloat;
        private long _updatedAtMs;
        private long _lastAnalysisMs;
        private long _lastClientRequestMs;
        private string? _lastError;
        private double _lastRms;
        private long _sampleFrames;
        private string _format = "";
        private IWaveIn? _capture;
        private string _targetApplication = "";
        private bool _targetPlaying;
        private bool _strictProcessCapture;

        public SpectrumAnalyzer()
        {
            for (int i = 0; i < FftLength; i++)
            {
                _window[i] = (float)(0.54 - 0.46 * Math.Cos(2 * Math.PI * i / (FftLength - 1)));
            }

            
            
            _idleTimer = new Timer(_ => QueueMaintenance(), null, 1000, 1000);
        }

        public void SetTargetApplication(string sourceAppId, bool isPlaying,
            bool strictProcessCapture)
        {
            bool sourceChanged;
            lock (_sync)
            {
                if (_targetApplication == sourceAppId && _targetPlaying == isPlaying &&
                    _strictProcessCapture == strictProcessCapture) return;
                sourceChanged = _targetApplication != sourceAppId ||
                    _strictProcessCapture != strictProcessCapture;
                if (_targetApplication != sourceAppId)
                {
                    _targetProcessId = 0;
                    _nextProcessLookupAt = 0;
                    _processRetryAt = 0;
                }
                _targetApplication = sourceAppId ?? "";
                _targetPlaying = isPlaying;
                _strictProcessCapture = strictProcessCapture;
                _nextProcessLookupAt = 0;
                _targetRevision++;
                _nextRetryAt = 0;
            }
            if (sourceChanged) StopCapture();
            QueueMaintenance();
        }

        public bool TryActivate()
        {
            Interlocked.Exchange(ref _lastClientRequestMs, Environment.TickCount64);
            lock (_sync)
            {
                if (_disposed != 0) return false;
                if (!_targetPlaying || Environment.TickCount64 < _nextRetryAt) return false;
                if (_capture != null && !_captureStopped) return true;
            }
            QueueMaintenance();
            return false;
        }

        private void QueueMaintenance()
        {
            if (Volatile.Read(ref _disposed) != 0) return;
            if (Interlocked.Exchange(ref _maintenanceQueued, 1) != 0)
            {
                Volatile.Write(ref _maintenanceAgain, 1);
                return;
            }
            _ = Task.Run(async () =>
            {
                await _lifecycle.WaitAsync().ConfigureAwait(false);
                try { await MaintainCaptureAsync().ConfigureAwait(false); }
                catch (Exception error)
                {
                    lock (_sync)
                    {
                        _lastError = error.Message;
                        _nextRetryAt = Environment.TickCount64 + Math.Min(30000, 500 * (1 << Math.Min(6, ++_failureCount)));
                    }
                    StopCapture();
                }
                finally
                {
                    _lifecycle.Release();
                    Volatile.Write(ref _maintenanceQueued, 0);
                    if (Interlocked.Exchange(ref _maintenanceAgain, 0) != 0) QueueMaintenance();
                }
            });
        }

        private async Task MaintainCaptureAsync()
        {
            long now = Environment.TickCount64;
            string target;
            int revision;
            bool demanded;
            bool strictProcess;
            lock (_sync)
            {
                demanded = _disposed == 0 && _targetPlaying &&
                    _lastClientRequestMs > 0 && now - _lastClientRequestMs <= ClientIdleTimeoutMs;
                target = _targetApplication;
                revision = _targetRevision;
                strictProcess = _strictProcessCapture;
            }
            if (!demanded)
            {
                StopCapture();
                return;
            }
            if (now < _nextRetryAt) return;
            if (_deviceEnumerator == null)
            {
                _deviceEnumerator = new MMDeviceEnumerator();
                _deviceEnumerator.RegisterEndpointNotificationCallback(this);
            }
            int deviceRevision = Volatile.Read(ref _deviceRevision);
            if (deviceRevision != _activeDeviceRevision && Volatile.Read(ref _lastDeviceChangeAt) > 0)
            {
                long deadline = now + 500;
                while (now < deadline)
                {
                    long remaining = Volatile.Read(ref _lastDeviceChangeAt) + 180 - now;
                    if (remaining <= 0) break;
                    await Task.Delay((int)Math.Min(remaining, deadline - now)).ConfigureAwait(false);
                    now = Environment.TickCount64;
                }
                deviceRevision = Volatile.Read(ref _deviceRevision);
            }
            if (deviceRevision != _activeDeviceRevision) _nextProcessLookupAt = 0;
            int pid = _targetProcessId;
            if (now >= _nextProcessLookupAt)
            {
                pid = ResolveProcessId(target);
                lock (_sync)
                {
                    if (_targetRevision != revision || _disposed != 0) return;
                    if (pid != _targetProcessId) { _targetProcessId = pid; _processRetryAt = 0; }
                }
                _nextProcessLookupAt = now + (pid == 0 ? 2000 : 10000);
            }
            bool useProcess = pid > 0 && ProcessLoopbackCapture.IsSupported && now >= _processRetryAt;
            if (strictProcess && !useProcess)
            {
                StopCapture();
                lock (_sync)
                {
                    _lastError = !ProcessLoopbackCapture.IsSupported
                        ? "Process loopback is unavailable on this Windows version."
                        : pid == 0
                            ? "Selected application's audio process was not found."
                            : "Selected application's process capture is retrying.";
                }
                return;
            }
            string desiredMode = useProcess ? "process" : "system";
            lock (_sync)
            {
                if (_capture != null && !_captureStopped && _activeTargetRevision == revision &&
                    _activeDeviceRevision == deviceRevision && _captureMode == desiredMode &&
                    (!useProcess || _activeProcessId == pid)) return;
            }
            StopCapture();
            IWaveIn? capture = null;
            try
            {
                if (useProcess)
                {
                    try { capture = await ProcessLoopbackCapture.CreateAsync(pid).ConfigureAwait(false); }
                    catch (Exception error)
                    {
                        _processRetryAt = now + 30000;
                        _lastError = $"Process capture unavailable: {error.Message}";
                    }
                }
                if (strictProcess && capture == null) return;
                capture ??= new WasapiLoopbackCapture();
                lock (_sync)
                {
                    if (_disposed != 0 || _targetRevision != revision ||
                        Environment.TickCount64 - _lastClientRequestMs > ClientIdleTimeoutMs) return;
                    _sampleRate = Math.Max(1, capture.WaveFormat.SampleRate);
                    _channels = Math.Max(1, capture.WaveFormat.Channels);
                    _bytesPerSample = Math.Max(1, (capture.WaveFormat.BitsPerSample + 7) / 8);
                    _isFloat = capture.WaveFormat.Encoding == WaveFormatEncoding.IeeeFloat ||
                        capture.WaveFormat is WaveFormatExtensible extensible && extensible.SubFormat == IeeeFloatSubFormat;
                    _format = $"{capture.WaveFormat.Encoding}/{_sampleRate}Hz/{_channels}ch/{capture.WaveFormat.BitsPerSample}bit";
                    _captureMode = capture is ProcessLoopbackCapture ? "process" : "system";
                    _activeProcessId = _captureMode == "process" ? pid : 0;
                    _activeTargetRevision = revision;
                    _activeDeviceRevision = deviceRevision;
                    _captureStopped = false;
                    PrepareBands();
                    capture.DataAvailable += OnDataAvailable;
                    capture.RecordingStopped += OnRecordingStopped;
                    _capture = capture;
                }
                _captureStartedAt = Environment.TickCount64;
                capture.StartRecording();
                capture = null;
                _nextRetryAt = 0;
                if (_captureMode == "process") _lastError = null;
            }
            finally
            {
                if (capture != null)
                {
                    lock (_sync) { if (ReferenceEquals(_capture, capture)) _capture = null; }
                    capture.DataAvailable -= OnDataAvailable;
                    capture.RecordingStopped -= OnRecordingStopped;
                    capture.Dispose();
                }
            }
        }

        private int _activeProcessId;

        private int ResolveProcessId(string target)
        {
            if (string.IsNullOrWhiteSpace(target)) return 0;
            var matches = new HashSet<int>();
            foreach (MMDevice device in _deviceEnumerator!.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active))
            {
                using (device)
                {
                    try
                    {
                        SessionCollection sessions = device.AudioSessionManager.Sessions;
                        for (int index = 0; index < sessions.Count; index++)
                        {
                            using AudioSessionControl session = sessions[index];
                            if (session.IsSystemSoundsSession || session.State == AudioSessionState.AudioSessionStateExpired) continue;
                            try
                            {
                                using Process process = Process.GetProcessById((int)session.GetProcessID);
                                if (MatchesApplication(target, process) ||
                                    (session.GetSessionIdentifier?.Contains(target, StringComparison.OrdinalIgnoreCase) ?? false))
                                    matches.Add(process.Id);
                            }
                            catch { }
                        }
                    }
                    catch { }
                }
            }
            
            return matches.Count == 1 ? matches.First() : 0;
        }

        private static bool MatchesApplication(string target, Process process)
        {
            string name = process.ProcessName;
            if (target.Equals(name, StringComparison.OrdinalIgnoreCase) ||
                target.Equals(name + ".exe", StringComparison.OrdinalIgnoreCase)) return true;
            if (target.Split(['.', '!', '_', '-', '\\', '/'], StringSplitOptions.RemoveEmptyEntries)
                .Any(part => part.Equals(name, StringComparison.OrdinalIgnoreCase))) return true;
            try
            {
                uint length = 0;
                if (GetApplicationUserModelId(process.Handle, ref length, null) != 122 || length == 0) return false;
                var appId = new StringBuilder((int)length);
                return GetApplicationUserModelId(process.Handle, ref length, appId) == 0 &&
                    target.Equals(appId.ToString(), StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetApplicationUserModelId(IntPtr process, ref uint length, StringBuilder? appId);

        public void OnDefaultDeviceChanged(DataFlow flow, Role role, string id)
        { if (flow == DataFlow.Render) NotifyDeviceChanged(); }
        public void OnDeviceStateChanged(string id, DeviceState state)
        { NotifyDeviceChanged(); }
        public void OnDeviceAdded(string id) { NotifyDeviceChanged(); }
        public void OnDeviceRemoved(string id) { NotifyDeviceChanged(); }
        public void OnPropertyValueChanged(string id, PropertyKey key) { }

        private void NotifyDeviceChanged()
        {
            Interlocked.Exchange(ref _lastDeviceChangeAt, Environment.TickCount64);
            Interlocked.Increment(ref _deviceRevision);
            lock (_sync)
            {
                _nextRetryAt = 0;
                _processRetryAt = 0;
            }
            QueueMaintenance();
        }

        private void OnRecordingStopped(object? sender, StoppedEventArgs e)
        {
            lock (_sync)
            {
                if (!ReferenceEquals(sender, _capture)) return;
                _captureStopped = true;
                _nextProcessLookupAt = 0;
                _lastError = e.Exception?.Message;
                _nextRetryAt = Environment.TickCount64 + Math.Min(30000, 1000 * (1 << Math.Min(5, _failureCount++)));
                if (_captureMode == "process") _processRetryAt = Environment.TickCount64 + 30000;
            }
            QueueMaintenance();
        }

        private void OnDataAvailable(object? sender, WaveInEventArgs e)
        {
            int frameBytes = _channels * _bytesPerSample;
            if (frameBytes <= 0 || e.BytesRecorded < frameBytes) return;

            ReadOnlySpan<byte> data = e.Buffer.AsSpan(0, e.BytesRecorded);
            lock (_sync)
            {
                if (!ReferenceEquals(sender, _capture) || !_targetPlaying || _disposed != 0) return;
                if (Environment.TickCount64 - _captureStartedAt > 5000) _failureCount = 0;
                for (int offset = 0; offset + frameBytes <= data.Length; offset += frameBytes)
                {
                    float mono = 0;
                    for (int channel = 0; channel < _channels; channel++)
                    {
                        mono += ReadSample(data.Slice(offset + channel * _bytesPerSample, _bytesPerSample));
                    }
                    mono /= _channels;
                    if (!float.IsFinite(mono)) mono = 0;

                    _ring[_writeIndex] = Math.Clamp(mono, -1f, 1f);
                    _writeIndex = (_writeIndex + 1) % FftLength;
                    if (_sampleCount < FftLength) _sampleCount++;
                    _samplesSinceAnalysis++;
                    _sampleFrames++;
                }

                long now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                if (_sampleCount == FftLength &&
                    _samplesSinceAnalysis >= AnalysisHopSamples &&
                    now - _lastAnalysisMs >= AnalysisIntervalMs)
                {
                    AnalyzeLocked();
                    _samplesSinceAnalysis = 0;
                    _lastAnalysisMs = now;
                }
            }
        }

        private float ReadSample(ReadOnlySpan<byte> sample)
        {
            if (_isFloat && _bytesPerSample >= 4)
            {
                return BitConverter.Int32BitsToSingle(BinaryPrimitives.ReadInt32LittleEndian(sample));
            }

            return _bytesPerSample switch
            {
                1 => (sample[0] - 128) / 128f,
                2 => BinaryPrimitives.ReadInt16LittleEndian(sample) / 32768f,
                3 => Read24BitSample(sample),
                _ => BinaryPrimitives.ReadInt32LittleEndian(sample) / 2147483648f,
            };
        }

        private static float Read24BitSample(ReadOnlySpan<byte> sample)
        {
            int value = sample[0] | (sample[1] << 8) | (sample[2] << 16);
            if ((value & 0x00800000) != 0) value |= unchecked((int)0xFF000000);
            return value / 8388608f;
        }

        private void AnalyzeLocked()
        {
            double sumSquares = 0;
            for (int i = 0; i < FftLength; i++)
            {
                int ringIndex = (_writeIndex + i) % FftLength;
                float sample = _ring[ringIndex];
                sumSquares += sample * sample;
                _fft[i].X = sample * _window[i];
                _fft[i].Y = 0;
            }

            FastFourierTransform.FFT(true, FftExponent, _fft);
            double rms = Math.Sqrt(sumSquares / FftLength);
            _lastRms = rms;
            for (int band = 0; band < BandCount; band++)
            {
                double energy = 0;
                for (int bin = _startBins[band]; bin < _endBins[band]; bin++)
                {
                    double real = _fft[bin].X;
                    double imaginary = _fft[bin].Y;
                    energy += Math.Sqrt(real * real + imaginary * imaginary);
                }
                double magnitude = energy / (_endBins[band] - _startBins[band]);
                double decibels = 20.0 * Math.Log10(magnitude + 1e-9);
                float target = rms < 0.0007 ? 0f :
                    (float)Math.Sqrt(Math.Clamp((decibels + 92.0) / 72.0, 0.0, 1.0));
                float smoothing = target > _levels[band] ? 0.62f : 0.18f;
                _levels[band] += (target - _levels[band]) * smoothing;
            }
            _updatedAtMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        }

        private void PrepareBands()
        {
            const double lowFrequency = 45.0;
            double highFrequency = Math.Min(16000.0, _sampleRate * 0.45);
            double frequencyRatio = highFrequency / lowFrequency;

            for (int band = 0; band < BandCount; band++)
            {
                double startFrequency = lowFrequency * Math.Pow(
                    frequencyRatio,
                    band / (double)BandCount
                );
                double endFrequency = lowFrequency * Math.Pow(
                    frequencyRatio,
                    (band + 1) / (double)BandCount
                );
                int startBin = Math.Clamp(
                    (int)Math.Floor(startFrequency * FftLength / _sampleRate),
                    1,
                    FftLength / 2 - 1
                );
                int endBin = Math.Clamp(
                    (int)Math.Ceiling(endFrequency * FftLength / _sampleRate),
                    startBin + 1,
                    FftLength / 2
                );

                _startBins[band] = startBin;
                _endBins[band] = endBin;
            }
        }

        public SpectrumSnapshot GetSnapshot()
        {
            lock (_sync)
            {
                long now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                long ageMs = _updatedAtMs <= 0 ? long.MaxValue : now - _updatedAtMs;
                float decay = ageMs <= 100
                    ? 1f
                    : (float)Math.Pow(0.78, (ageMs - 100) / 50.0);
                if (ageMs > 900) decay = 0;

                var snapshot = new float[BandCount];
                for (int i = 0; i < BandCount; i++)
                {
                    snapshot[i] = Math.Clamp(_levels[i] * decay, 0f, 1f);
                }
                return new SpectrumSnapshot(
                    snapshot,
                    _updatedAtMs,
                    _capture != null && !_captureStopped,
                    _lastError,
                    _lastRms,
                    _sampleFrames,
                    _format,
                    _captureMode,
                    _activeProcessId
                );
            }
        }

        public byte[] GetCompactSnapshot(bool activationAvailable)
        {
            lock (_sync)
            {
                const int headerSize = 12;
                byte[] packet = new byte[headerSize + BandCount * sizeof(float)];
                packet[0] = 1;
                packet[1] = (byte)((activationAvailable || (_capture != null && !_captureStopped)) ? 1 : 0);
                BinaryPrimitives.WriteUInt16LittleEndian(
                    packet.AsSpan(2, sizeof(ushort)),
                    (ushort)BandCount
                );
                BinaryPrimitives.WriteInt64LittleEndian(
                    packet.AsSpan(4, sizeof(long)),
                    _updatedAtMs
                );

                long now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                long ageMs = _updatedAtMs <= 0 ? long.MaxValue : now - _updatedAtMs;
                float decay = ageMs <= 100
                    ? 1f
                    : (float)Math.Pow(0.78, (ageMs - 100) / 50.0);
                if (ageMs > 900) decay = 0;

                for (int i = 0; i < BandCount; i++)
                {
                    float level = Math.Clamp(_levels[i] * decay, 0f, 1f);
                    BinaryPrimitives.WriteSingleLittleEndian(
                        packet.AsSpan(headerSize + i * sizeof(float), sizeof(float)),
                        level
                    );
                }
                return packet;
            }
        }

        private void StopCapture()
        {
            IWaveIn? capture;
            lock (_sync)
            {
                capture = _capture;
                _capture = null;
                _captureMode = "idle";
                _activeProcessId = 0;
                _writeIndex = 0;
                _sampleCount = 0;
                _samplesSinceAnalysis = 0;
                Array.Clear(_levels);
                _updatedAtMs = 0;
            }

            if (capture == null) return;
            capture.DataAvailable -= OnDataAvailable;
            capture.RecordingStopped -= OnRecordingStopped;
            try { capture.StopRecording(); } catch { }
            try { capture.Dispose(); } catch { }
        }

        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
            _idleTimer.Dispose();
            _lifecycle.Wait();
            try
            {
                StopCapture();
                if (_deviceEnumerator != null)
                {
                    _deviceEnumerator.UnregisterEndpointNotificationCallback(this);
                    _deviceEnumerator.Dispose();
                    _deviceEnumerator = null;
                }
            }
            finally { _lifecycle.Release(); }
        }
    }
}
