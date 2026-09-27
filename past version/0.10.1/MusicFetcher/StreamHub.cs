using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Channels;

namespace MusicFetcher;

internal sealed class StreamHub : IAsyncDisposable
{
    private const uint Magic = 0x3153574D;
    private const byte ProtocolVersion = 1;
    private const int HeaderSize = 12;
    private const int MaxPayloadSize = 20 * 1024 * 1024;
    private const byte InfoType = 1;
    private const byte SpectrumType = 2;
    private const byte HeartbeatType = 3;
    private const byte ArtworkType = 4;
    private const byte SetSpectrumType = 16;
    private const byte CommandType = 17;

    private readonly TcpListener _listener = new(IPAddress.Loopback, 12581);
    private readonly ConcurrentDictionary<int, ClientConnection> _clients = new();
    private readonly CancellationTokenSource _shutdown = new();
    private readonly Func<byte[]> _getCurrentInfo;
    private readonly Func<(string Version, byte[] Bytes)> _getCurrentArtwork;
    private readonly Func<byte[]> _getSpectrum;
    private readonly Func<byte, Task> _handleCommand;
    private int _nextClientId;
    private readonly SemaphoreSlim _spectrumWake = new(0, 1);
    private Task[] _tasks = [];

    public StreamHub(
        Func<byte[]> getCurrentInfo,
        Func<(string Version, byte[] Bytes)> getCurrentArtwork,
        Func<byte[]> getSpectrum,
        Func<byte, Task> handleCommand)
    {
        _getCurrentInfo = getCurrentInfo;
        _getCurrentArtwork = getCurrentArtwork;
        _getSpectrum = getSpectrum;
        _handleCommand = handleCommand;
    }

    public void Start()
    {
        _listener.Start();
        _tasks = [Task.Run(AcceptLoopAsync), Task.Run(SpectrumLoopAsync), Task.Run(HeartbeatLoopAsync)];
    }

    public void PublishInfo(byte[] payload) => Broadcast(InfoType, payload, spectrumOnly: false);

    public void PublishArtwork(string version, byte[] bytes)
    {
        if (version.Length == 0 || bytes.Length == 0) return;
        Broadcast(ArtworkType, EncodeArtwork(version, bytes), spectrumOnly: false);
    }

    private static byte[] EncodeArtwork(string version, byte[] bytes)
    {
        byte[] versionBytes = Encoding.UTF8.GetBytes(version);
        if (versionBytes.Length > ushort.MaxValue)
            throw new InvalidDataException("Artwork version is too long.");
        byte[] payload = new byte[2 + versionBytes.Length + bytes.Length];
        BinaryPrimitives.WriteUInt16LittleEndian(payload, (ushort)versionBytes.Length);
        versionBytes.CopyTo(payload, 2);
        bytes.CopyTo(payload, 2 + versionBytes.Length);
        return payload;
    }

    private async Task AcceptLoopAsync()
    {
        while (!_shutdown.IsCancellationRequested)
        {
            try
            {
                TcpClient client = await _listener.AcceptTcpClientAsync(_shutdown.Token);
                client.NoDelay = true;
                int id = Interlocked.Increment(ref _nextClientId);
                var connection = new ClientConnection(id, client, RemoveClient, _handleCommand, WakeSpectrum);
                _clients[id] = connection;
                connection.Enqueue(InfoType, _getCurrentInfo());
                var artwork = _getCurrentArtwork();
                if (artwork.Version.Length > 0 && artwork.Bytes.Length > 0)
                    connection.Enqueue(ArtworkType, EncodeArtwork(artwork.Version, artwork.Bytes));
                connection.Start();
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception error)
            {
                Console.Error.WriteLine($"[Stream] accept failed: {error.Message}");
                await Task.Delay(500, _shutdown.Token).ConfigureAwait(false);
            }
        }
    }

    private async Task SpectrumLoopAsync()
    {
        try
        {
            while (!_shutdown.IsCancellationRequested)
            {
                if (!_clients.Values.Any(client => client.SpectrumEnabled))
                {
                    await _spectrumWake.WaitAsync(_shutdown.Token).ConfigureAwait(false);
                    continue;
                }
                byte[] spectrum = _getSpectrum();
                Broadcast(SpectrumType, spectrum, spectrumOnly: true);
                await Task.Delay(spectrum.Length > 1 && spectrum[1] != 0 ? 33 : 250,
                    _shutdown.Token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) { }
    }

    private async Task HeartbeatLoopAsync()
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(1));
        try
        {
            while (await timer.WaitForNextTickAsync(_shutdown.Token))
            {
                Broadcast(HeartbeatType, Array.Empty<byte>(), spectrumOnly: false);
            }
        }
        catch (OperationCanceledException) { }
    }

    private void Broadcast(byte type, byte[] payload, bool spectrumOnly)
    {
        foreach (ClientConnection client in _clients.Values)
        {
            if (!spectrumOnly || client.SpectrumEnabled) client.Enqueue(type, payload);
        }
    }

    private void RemoveClient(int id) => _clients.TryRemove(id, out _);

    private void WakeSpectrum()
    {
        try { _spectrumWake.Release(); } catch (SemaphoreFullException) { }
    }

    public async ValueTask DisposeAsync()
    {
        _shutdown.Cancel();
        _listener.Stop();
        foreach (ClientConnection client in _clients.Values) await client.DisposeAsync();
        _clients.Clear();
        try { await Task.WhenAll(_tasks); } catch (OperationCanceledException) { }
        _shutdown.Dispose();
    }

    private sealed record OutboundFrame(byte Type, byte[] Payload);

    private sealed class ClientConnection : IAsyncDisposable
    {
        private readonly int _id;
        private readonly TcpClient _client;
        private readonly NetworkStream _stream;
        private readonly Action<int> _onClosed;
        private readonly Func<byte, Task> _handleCommand;
        private readonly Action _wakeSpectrum;
        private readonly CancellationTokenSource _shutdown = new();
        private readonly Channel<OutboundFrame> _outbound = Channel.CreateBounded<OutboundFrame>(
            new BoundedChannelOptions(8)
            {
                FullMode = BoundedChannelFullMode.Wait,
                SingleReader = true,
                SingleWriter = false
            }
        );
        private readonly SemaphoreSlim _outboundWake = new(0, 1);
        private OutboundFrame? _pendingSpectrum;
        private int _spectrumEnabled;
        private int _closed;

        public ClientConnection(
            int id,
            TcpClient client,
            Action<int> onClosed,
            Func<byte, Task> handleCommand,
            Action wakeSpectrum)
        {
            _id = id;
            _client = client;
            _stream = client.GetStream();
            _onClosed = onClosed;
            _handleCommand = handleCommand;
            _wakeSpectrum = wakeSpectrum;
        }

        public bool SpectrumEnabled => Volatile.Read(ref _spectrumEnabled) != 0;

        public void Start()
        {
            _ = Task.Run(ReadLoopAsync);
            _ = Task.Run(WriteLoopAsync);
        }

        public void Enqueue(byte type, byte[] payload)
        {
            if (Volatile.Read(ref _closed) != 0) return;
            if (type == SpectrumType)
            {
                Interlocked.Exchange(ref _pendingSpectrum, new OutboundFrame(type, payload));
                WakeWriter();
                return;
            }
            if (!_outbound.Writer.TryWrite(new OutboundFrame(type, payload))) Close();
            else WakeWriter();
        }

        private void WakeWriter()
        {
            try { _outboundWake.Release(); } catch (SemaphoreFullException) { }
        }

        private async Task ReadLoopAsync()
        {
            byte[] header = new byte[HeaderSize];
            try
            {
                while (!_shutdown.IsCancellationRequested)
                {
                    await _stream.ReadExactlyAsync(header, _shutdown.Token);
                    if (BinaryPrimitives.ReadUInt32LittleEndian(header) != Magic ||
                        header[4] != ProtocolVersion)
                        break;
                    byte type = header[5];
                    int length = BinaryPrimitives.ReadInt32LittleEndian(header.AsSpan(8));
                    if (length < 0 || length > MaxPayloadSize) break;
                    byte[] payload = new byte[length];
                    if (length > 0) await _stream.ReadExactlyAsync(payload, _shutdown.Token);
                    if (type == SetSpectrumType && payload.Length == 1)
                    {
                        Volatile.Write(ref _spectrumEnabled, payload[0] == 0 ? 0 : 1);
                        _wakeSpectrum();
                    }
                    else if (type == CommandType && payload.Length == 1)
                        await _handleCommand(payload[0]).ConfigureAwait(false);
                }
            }
            catch (OperationCanceledException) { }
            catch (EndOfStreamException) { }
            catch (IOException) { }
            catch (ObjectDisposedException) { }
            finally
            {
                Close();
            }
        }

        private async Task WriteLoopAsync()
        {
            byte[] header = new byte[HeaderSize];
            try
            {
                while (!_shutdown.IsCancellationRequested)
                {
                    if (!_outbound.Reader.TryRead(out OutboundFrame? frame))
                    {
                        frame = Interlocked.Exchange(ref _pendingSpectrum, null);
                        if (frame == null)
                        {
                            await _outboundWake.WaitAsync(_shutdown.Token);
                            continue;
                        }
                    }
                    BinaryPrimitives.WriteUInt32LittleEndian(header, Magic);
                    header[4] = ProtocolVersion;
                    header[5] = frame.Type;
                    header[6] = 0;
                    header[7] = 0;
                    BinaryPrimitives.WriteInt32LittleEndian(header.AsSpan(8), frame.Payload.Length);
                    await _stream.WriteAsync(header, _shutdown.Token);
                    if (frame.Payload.Length > 0)
                        await _stream.WriteAsync(frame.Payload, _shutdown.Token);
                }
            }
            catch (OperationCanceledException) { }
            catch (IOException) { }
            catch (ObjectDisposedException) { }
            finally
            {
                Close();
            }
        }

        private void Close()
        {
            if (Interlocked.Exchange(ref _closed, 1) != 0) return;
            _shutdown.Cancel();
            _outbound.Writer.TryComplete();
            _client.Dispose();
            _onClosed(_id);
        }

        public ValueTask DisposeAsync()
        {
            Close();
            _shutdown.Dispose();
            return ValueTask.CompletedTask;
        }
    }
}
