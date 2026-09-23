using System.Runtime.InteropServices;
using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;
using NAudio.Wasapi.CoreAudioApi.Interfaces;
using NAudio.Wave;

namespace MusicFetcher;

internal sealed class ProcessLoopbackCapture : IWaveIn
{
    private readonly AudioClient _client;
    private readonly AutoResetEvent _ready = new(false);
    private readonly ManualResetEvent _stop = new(false);
    private Thread? _thread;
    private int _disposed;
    private WaveFormat _format = new(48000, 16, 2);

    public static bool IsSupported => OperatingSystem.IsWindowsVersionAtLeast(10, 0, 20348);
    public event EventHandler<WaveInEventArgs>? DataAvailable;
    public event EventHandler<StoppedEventArgs>? RecordingStopped;
    public WaveFormat WaveFormat
    {
        get => _format;
        set => throw new NotSupportedException("Capture format is fixed.");
    }

    private ProcessLoopbackCapture(AudioClient client)
    {
        _client = client;
        try
        {
            _client.Initialize(AudioClientShareMode.Shared,
                AudioClientStreamFlags.Loopback | AudioClientStreamFlags.EventCallback |
                AudioClientStreamFlags.AutoConvertPcm, 0, 0, _format, Guid.Empty);
            _client.SetEventHandle(_ready.SafeWaitHandle.DangerousGetHandle());
        }
        catch
        {
            _client.Dispose();
            _ready.Dispose();
            _stop.Dispose();
            throw;
        }
    }

    public static async Task<ProcessLoopbackCapture> CreateAsync(int processId)
    {
        if (!IsSupported || processId <= 0) throw new PlatformNotSupportedException();
        var completion = new ActivationCompletion(processId);
        IActivateAudioInterfaceAsyncOperation? operation = null;
        try
        {
            Guid iid = typeof(IAudioClient).GUID;
            Marshal.ThrowExceptionForHR(ActivateAudioInterfaceAsync(
                "VAD\\Process_Loopback", ref iid, completion.Parameters, completion, out operation));
            AudioClient client;
            try
            {
                client = await completion.Result.Task.WaitAsync(TimeSpan.FromSeconds(3)).ConfigureAwait(false);
            }
            catch (TimeoutException)
            {
                
                _ = completion.Result.Task.ContinueWith(task =>
                {
                    if (task.IsCompletedSuccessfully) task.Result.Dispose();
                    else _ = task.Exception;
                }, TaskScheduler.Default);
                throw;
            }
            return new ProcessLoopbackCapture(client);
        }
        catch
        {
            if (operation == null) completion.ReleaseParameters();
            throw;
        }
        finally
        {
            if (operation != null) Marshal.ReleaseComObject(operation);
            GC.KeepAlive(completion);
        }
    }

    public void StartRecording()
    {
        ObjectDisposedException.ThrowIf(_disposed != 0, this);
        if (_thread != null) throw new InvalidOperationException("Already started.");
        _client.Start();
        _thread = new Thread(Capture) { IsBackground = true, Name = "Music process audio" };
        _thread.SetApartmentState(ApartmentState.MTA);
        _thread.Start();
    }

    private void Capture()
    {
        Exception? failure = null;
        try
        {
            AudioCaptureClient reader = _client.AudioCaptureClient;
            byte[] buffer = new byte[Math.Max(1, _client.BufferSize) * _format.BlockAlign];
            WaitHandle[] signals = [_stop, _ready];
            while (WaitHandle.WaitAny(signals, 1000) != 0)
            {
                while (!_stop.WaitOne(0) && reader.GetNextPacketSize() > 0)
                {
                    IntPtr data = reader.GetBuffer(out int frames, out AudioClientBufferFlags flags);
                    int bytes = checked(frames * _format.BlockAlign);
                    try
                    {
                        if (buffer.Length < bytes) Array.Resize(ref buffer, bytes);
                        if ((flags & AudioClientBufferFlags.Silent) != 0) Array.Clear(buffer, 0, bytes);
                        else Marshal.Copy(data, buffer, 0, bytes);
                    }
                    finally { reader.ReleaseBuffer(frames); }
                    if (bytes > 0) DataAvailable?.Invoke(this, new WaveInEventArgs(buffer, bytes));
                }
            }
        }
        catch (Exception error) { failure = error; }
        finally
        {
            try { _client.Stop(); } catch { }
            RecordingStopped?.Invoke(this, new StoppedEventArgs(failure));
        }
    }

    public void StopRecording()
    {
        _stop.Set();
        if (_thread != null && Thread.CurrentThread != _thread) _thread.Join();
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
        StopRecording();
        _client.Dispose();
        _ready.Dispose();
        _stop.Dispose();
    }

    [DllImport("Mmdevapi.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
    private static extern int ActivateAudioInterfaceAsync(string device, ref Guid iid,
        IntPtr parameters, IActivateAudioInterfaceCompletionHandler completion,
        out IActivateAudioInterfaceAsyncOperation operation);

    [StructLayout(LayoutKind.Sequential)]
    private struct ActivationParameters { public int Type; public uint Pid; public int Mode; }

    [StructLayout(LayoutKind.Sequential)]
    private struct Blob { public int Length; public IntPtr Data; }

    [StructLayout(LayoutKind.Explicit)]
    private struct Variant
    {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(8)] public Blob Blob;
    }

    [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
    private sealed class ActivationCompletion : IActivateAudioInterfaceCompletionHandler
    {
        private IntPtr _data;
        private IntPtr _parameters;
        public IntPtr Parameters => _parameters;
        public TaskCompletionSource<AudioClient> Result { get; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        public ActivationCompletion(int pid)
        {
            var args = new ActivationParameters { Type = 1, Pid = (uint)pid, Mode = 0 };
            _data = Marshal.AllocHGlobal(Marshal.SizeOf<ActivationParameters>());
            Marshal.StructureToPtr(args, _data, false);
            var variant = new Variant { Type = 65,
                Blob = new Blob { Length = Marshal.SizeOf<ActivationParameters>(), Data = _data } };
            _parameters = Marshal.AllocHGlobal(Marshal.SizeOf<Variant>());
            Marshal.StructureToPtr(variant, _parameters, false);
        }

        public void ActivateCompleted(IActivateAudioInterfaceAsyncOperation operation)
        {
            object? activated = null;
            try
            {
                operation.GetActivateResult(out int hr, out activated);
                Marshal.ThrowExceptionForHR(hr);
                var client = new AudioClient((IAudioClient)activated);
                activated = null;
                Result.TrySetResult(client);
            }
            catch (Exception error) { Result.TrySetException(error); }
            finally
            {
                if (activated != null && Marshal.IsComObject(activated)) Marshal.ReleaseComObject(activated);
                ReleaseParameters();
            }
        }

        public void ReleaseParameters()
        {
            IntPtr parameters = Interlocked.Exchange(ref _parameters, IntPtr.Zero);
            IntPtr data = Interlocked.Exchange(ref _data, IntPtr.Zero);
            if (parameters != IntPtr.Zero) Marshal.FreeHGlobal(parameters);
            if (data != IntPtr.Zero) Marshal.FreeHGlobal(data);
        }
    }
}
