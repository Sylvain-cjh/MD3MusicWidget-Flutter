using System;
using System.Buffers.Binary;
using System.Threading;
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
        string Format
    );

    internal sealed class SpectrumAnalyzer : IDisposable
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
        private long _lastStartAttemptMs;
        private string? _lastError;
        private double _lastRms;
        private long _sampleFrames;
        private string _format = "";
        private WasapiLoopbackCapture? _capture;

        public SpectrumAnalyzer()
        {
            for (int i = 0; i < FftLength; i++)
            {
                _window[i] = (float)(0.54 - 0.46 * Math.Cos(2 * Math.PI * i / (FftLength - 1)));
            }

            
            
            _idleTimer = new Timer(_ => StopIfIdle(), null, 1000, 1000);
        }

        public bool TryActivate()
        {
            long now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            Interlocked.Exchange(ref _lastClientRequestMs, now);

            lock (_sync)
            {
                if (_capture != null) return true;
                if (now - _lastStartAttemptMs < 1000) return false;
                _lastStartAttemptMs = now;

                WasapiLoopbackCapture? capture = null;
                try
                {
                    capture = new WasapiLoopbackCapture();
                    _sampleRate = Math.Max(1, capture.WaveFormat.SampleRate);
                    _channels = Math.Max(1, capture.WaveFormat.Channels);
                    _bytesPerSample = Math.Max(1, (capture.WaveFormat.BitsPerSample + 7) / 8);
                    _isFloat =
                        capture.WaveFormat.Encoding == WaveFormatEncoding.IeeeFloat ||
                        capture.WaveFormat is WaveFormatExtensible extensible &&
                        extensible.SubFormat == IeeeFloatSubFormat;
                    _format =
                        $"{capture.WaveFormat.Encoding}/{capture.WaveFormat.SampleRate}Hz/" +
                        $"{capture.WaveFormat.Channels}ch/{capture.WaveFormat.BitsPerSample}bit/float={_isFloat}";

                    capture.DataAvailable += OnDataAvailable;
                    capture.RecordingStopped += OnRecordingStopped;
                    _capture = capture;
                    capture.StartRecording();
                    _lastError = null;
                    return true;
                }
                catch (Exception ex)
                {
                    _lastError = ex.Message;
                    if (capture != null)
                    {
                        capture.DataAvailable -= OnDataAvailable;
                        capture.RecordingStopped -= OnRecordingStopped;
                        try { capture.Dispose(); } catch { }
                    }
                    _capture = null;
                    return false;
                }
            }
        }

        private void StopIfIdle()
        {
            long lastRequest = Interlocked.Read(ref _lastClientRequestMs);
            if (lastRequest <= 0) return;

            long now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            if (now - lastRequest > ClientIdleTimeoutMs)
            {
                StopCapture();
            }
        }

        private void OnRecordingStopped(object? sender, StoppedEventArgs e)
        {
            lock (_sync)
            {
                if (ReferenceEquals(sender, _capture)) _capture = null;
                Array.Clear(_levels);
                _sampleCount = 0;
                _samplesSinceAnalysis = 0;
                _updatedAtMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            }
        }

        private void OnDataAvailable(object? sender, WaveInEventArgs e)
        {
            int frameBytes = _channels * _bytesPerSample;
            if (frameBytes <= 0 || e.BytesRecorded < frameBytes) return;

            ReadOnlySpan<byte> data = e.Buffer.AsSpan(0, e.BytesRecorded);
            lock (_sync)
            {
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

                double energy = 0;
                int bins = 0;
                for (int bin = startBin; bin < endBin; bin++)
                {
                    double real = _fft[bin].X;
                    double imaginary = _fft[bin].Y;
                    
                    
                    
                    energy += Math.Sqrt(real * real + imaginary * imaginary);
                    bins++;
                }

                double magnitude = bins > 0 ? energy / bins : 0;
                double decibels = 20.0 * Math.Log10(magnitude + 1e-9);
                float target = rms < 0.0007
                    ? 0f
                    : (float)Math.Sqrt(Math.Clamp((decibels + 92.0) / 72.0, 0.0, 1.0));
                float smoothing = target > _levels[band] ? 0.62f : 0.18f;
                _levels[band] += (target - _levels[band]) * smoothing;
            }

            _updatedAtMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
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
                    _capture != null,
                    _lastError,
                    _lastRms,
                    _sampleFrames,
                    _format
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
                packet[1] = (byte)((activationAvailable || _capture != null) ? 1 : 0);
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
            WasapiLoopbackCapture? capture;
            lock (_sync)
            {
                capture = _capture;
                _capture = null;
                Array.Clear(_levels);
                _sampleCount = 0;
                _samplesSinceAnalysis = 0;
            }

            if (capture == null) return;
            capture.DataAvailable -= OnDataAvailable;
            capture.RecordingStopped -= OnRecordingStopped;
            try { capture.StopRecording(); } catch { }
            capture.Dispose();
        }

        public void Dispose()
        {
            _idleTimer.Dispose();
            StopCapture();
        }
    }
}
