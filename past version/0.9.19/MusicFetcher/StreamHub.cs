using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Threading.Channels;

namespace MusicFetcher;

internal sealed class StreamHub : IAsyncDisposable
{
    private const uint Magic = 0x3153574D;
    private const byte ProtocolVersion = 1;
    private const int HeaderSize = 12;
    private const int MaxPayloadSize = 16 * 1024 * 1024;
    private const byte InfoType = 1;
    private const byte SpectrumType = 2;
    private const byte HeartbeatType = 3;
    private const byte SetSpectrumType = 16;

    private readonly TcpListener _listener = new(IPAddress.Loopback, 12581);
    private readonly ConcurrentDictionary<int, ClientConnection> _clients = new();
    private readonly CancellationTokenSource _shutdown = new();
    private readonly Func<byte[]> _getCurrentInfo;
    private readonly Func<byte[]> _getSpectrum;
    private int _nextClientId;

    public StreamHub(Func<byte[]> getCurrentInfo, Func<byte[]> getSpectrum)
    {
        _getCurrentInfo = getCurrentInfo;
        _getSpectrum = getSpectrum;
    }

    public void Start()
    {
        _listener.Start();
        _ = Task.Run(AcceptLoopAsync);
        _ = Task.Run(SpectrumLoopAsync);
        _ = Task.Run(HeartbeatLoopAsync);
    }

    public void PublishInfo(byte[] payload) => Broadcast(InfoType, payload, spectrumOnly: false);

    private async Task AcceptLoopAsync()
    {
        while (!_shutdown.IsCancellationRequested)
        {
            try
            {
                TcpClient client = await _listener.AcceptTcpClientAsync(_shutdown.Token);
                client.NoDelay = true;
                int id = Interlocked.Increment(ref _nextClientId);
                var connection = new ClientConnection(id, client, RemoveClient);
                _clients[id] = connection;
                connection.Enqueue(InfoType, _getCurrentInfo());
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
        using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(33));
        try
        {
            while (await timer.WaitForNextTickAsync(_shutdown.Token))
            {
                if (!_clients.Values.Any(client => client.SpectrumEnabled)) continue;
                Broadcast(SpectrumType, _getSpectrum(), spectrumOnly: true);
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

    public async ValueTask DisposeAsync()
    {
        _shutdown.Cancel();
        _listener.Stop();
        foreach (ClientConnection client in _clients.Values) await client.DisposeAsync();
        _clients.Clear();
        _shutdown.Dispose();
    }

    private readonly record struct OutboundFrame(byte Type, byte[] Payload);

    private sealed class ClientConnection : IAsyncDisposable
    {
        private readonly int _id;
        private readonly TcpClient _client;
        private readonly NetworkStream _stream;
        private readonly Action<int> _onClosed;
        private readonly CancellationTokenSource _shutdown = new();
        private readonly Channel<OutboundFrame> _outbound = Channel.CreateBounded<OutboundFrame>(
            new BoundedChannelOptions(4)
            {
                FullMode = BoundedChannelFullMode.DropOldest,
                SingleReader = true,
                SingleWriter = false
            }
        );
        private int _spectrumEnabled;
        private int _closed;

        public ClientConnection(int id, TcpClient client, Action<int> onClosed)
        {
            _id = id;
            _client = client;
            _stream = client.GetStream();
            _onClosed = onClosed;
        }

        public bool SpectrumEnabled => Volatile.Read(ref _spectrumEnabled) != 0;

        public void Start()
        {
            _ = Task.Run(ReadLoopAsync);
            _ = Task.Run(WriteLoopAsync);
        }

        public void Enqueue(byte type, byte[] payload)
        {
            if (Volatile.Read(ref _closed) == 0)
                _outbound.Writer.TryWrite(new OutboundFrame(type, payload));
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
                        Volatile.Write(ref _spectrumEnabled, payload[0] == 0 ? 0 : 1);
                }
            }
            catch (OperationCanceledException) { }
            catch (EndOfStreamException) { }
            catch (IOException) { }
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
                await foreach (OutboundFrame frame in _outbound.Reader.ReadAllAsync(_shutdown.Token))
                {
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
