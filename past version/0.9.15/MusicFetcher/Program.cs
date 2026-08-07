using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Windows.Foundation;
using Windows.Media.Control;
using Windows.Storage.Streams;

namespace MusicFetcher
{
    class Program
    {
        private static readonly int ProcessId = Environment.ProcessId;
        private static string _currentJson = JsonSerializer.Serialize(new
        {
            processId = ProcessId,
            isPlaying = false,
            title = "暂无音乐播放",
            artist = "请打开播放软件",
            hasCover = false,
            coverVersion = "",
            trackVersion = "",
            positionMs = 0,
            durationMs = 0,
            timelineUpdatedAtMs = 0,
            fetcherUpdatedAtMs = 0
        });
        private static byte[] _currentCover = Array.Empty<byte>();
        private static string _currentCoverVersion = "";
        private static readonly object _stateLock = new();
        private static readonly SpectrumAnalyzer _spectrumAnalyzer = new();
        private static GlobalSystemMediaTransportControlsSessionManager? _manager;
        private static readonly TimeSpan MediaPropertiesTimeout = TimeSpan.FromMilliseconds(900);
        private static readonly TimeSpan ThumbnailOpenTimeout = TimeSpan.FromMilliseconds(650);
        private static readonly TimeSpan ThumbnailReadTimeout = TimeSpan.FromMilliseconds(900);
        private static long _lastErrorLogAtMs;

        private static async Task<T> AwaitWinRtAsync<T>(
            IAsyncOperation<T> operation,
            TimeSpan timeout
        )
        {
            try
            {
                return await operation.AsTask().WaitAsync(timeout);
            }
            catch (TimeoutException)
            {
                try { operation.Cancel(); } catch { }
                throw;
            }
        }

        private static void LogSmtcFailure(Exception exception)
        {
            long now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            if (now - _lastErrorLogAtMs < 2000) return;
            _lastErrorLogAtMs = now;
            Console.Error.WriteLine($"[SMTC] 状态读取失败，将自动重试: {exception.GetType().Name}: {exception.Message}");
        }

        private static async Task<bool> EnsureMediaManagerAsync()
        {
            if (_manager != null) return true;
            try
            {
                _manager = await AwaitWinRtAsync(
                    GlobalSystemMediaTransportControlsSessionManager.RequestAsync(),
                    TimeSpan.FromSeconds(2)
                );
                return _manager != null;
            }
            catch (Exception ex)
            {
                LogSmtcFailure(ex);
                _manager = null;
                return false;
            }
        }

        static async Task Main(string[] args)
        {
            Console.WriteLine("=========================================");
            Console.WriteLine("🚀 [SMTC Base64 融合内核] 已经启动...");
            Console.WriteLine("=========================================\n");

            try
            {
                
                
                
                _ = Task.Run(StartSmtcListeningLoop);

                
                
                
                TcpListener listener = new TcpListener(IPAddress.Loopback, 12580);
                listener.Start();

                while (true)
                {
                    TcpClient client = await listener.AcceptTcpClientAsync();
                    _ = Task.Run(() => HandleFlutterRequest(client));
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[致命异常] 本地服务停止: {ex}");
            }
        }

        private static async Task StartSmtcListeningLoop()
        {
            string? lastTitle = null;
            string? lastArtist = null;
            string lastSourceApp = "";
            bool lastPlayingState = false;
            string lastCoverVersion = "";
            double lastPositionMs = -1;
            double lastDurationMs = -1;
            long trackVersion = 0;
            long lastPublishedAtMs = 0;

            while (true)
            {
                try
                {
                    if (!await EnsureMediaManagerAsync())
                    {
                        await Task.Delay(400);
                        continue;
                    }
                    var session = _manager?.GetCurrentSession();
                    long now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                    if (session != null)
                    {
                        var props = await AwaitWinRtAsync(
                            session.TryGetMediaPropertiesAsync(),
                            MediaPropertiesTimeout
                        );
                        var playback = session.GetPlaybackInfo();

                        bool isPlaying = playback.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
                        string title = props.Title ?? "未知歌曲";
                        string artist = props.Artist ?? "未知歌手";
                        string sourceApp = session.SourceAppUserModelId ?? "";
                        var timeline = session.GetTimelineProperties();
                        var capturedAt = DateTimeOffset.UtcNow;
                        double durationMs = Math.Max(0, (timeline.EndTime - timeline.StartTime).TotalMilliseconds);
                        double elapsedSinceTimelineUpdateMs =
                            timeline.LastUpdatedTime == default ||
                            timeline.LastUpdatedTime > capturedAt
                                ? 0
                                : Math.Max(
                                    0,
                                    (capturedAt - timeline.LastUpdatedTime).TotalMilliseconds
                                );
                        double positionMs = Math.Max(
                            0,
                            timeline.Position.TotalMilliseconds + (isPlaying ? elapsedSinceTimelineUpdateMs : 0)
                        );
                        if (durationMs > 0)
                        {
                            positionMs = Math.Min(positionMs, durationMs);
                        }
                        long timelineUpdatedAtMs = capturedAt.ToUnixTimeMilliseconds();

                        bool positionRewound =
                            lastPositionMs > 5000 && positionMs + 1500 < lastPositionMs;
                        bool durationChanged =
                            lastDurationMs > 0 && durationMs > 0 &&
                            Math.Abs(durationMs - lastDurationMs) > 1500;
                        bool trackChanged = title != lastTitle ||
                            artist != lastArtist ||
                            sourceApp != lastSourceApp ||
                            positionRewound ||
                            durationChanged;
                        if (trackChanged)
                        {
                            trackVersion++;
                            lock (_stateLock)
                            {
                                _currentCover = Array.Empty<byte>();
                                _currentCoverVersion = "";
                            }
                        }

                        string coverVersion;
                        lock (_stateLock) coverVersion = _currentCoverVersion;

                        if (coverVersion.Length == 0 && props.Thumbnail != null)
                        {
                            try
                            {
                                using var stream = await AwaitWinRtAsync(
                                    props.Thumbnail.OpenReadAsync(),
                                    ThumbnailOpenTimeout
                                );
                                if (stream.Size > 16 * 1024 * 1024) throw new InvalidDataException("封面过大");
                                using var reader = new DataReader(stream);
                                uint coverSize = (uint)stream.Size;
                                await AwaitWinRtAsync(
                                    reader.LoadAsync(coverSize),
                                    ThumbnailReadTimeout
                                );
                                byte[] cover = new byte[(int)coverSize];
                                reader.ReadBytes(cover);
                                coverVersion = Convert.ToHexString(SHA256.HashData(cover));
                                lock (_stateLock)
                                {
                                    _currentCover = cover;
                                    _currentCoverVersion = coverVersion;
                                }
                            }
                            catch { }
                        }

                        bool needJsonUpdate = trackChanged ||
                            isPlaying != lastPlayingState ||
                            coverVersion != lastCoverVersion ||
                            Math.Abs(positionMs - lastPositionMs) >= 100 ||
                            durationMs != lastDurationMs ||
                            now - lastPublishedAtMs >= 500;

                        if (needJsonUpdate)
                        {
                            var info = new
                            {
                                processId = ProcessId,
                                isPlaying,
                                title,
                                artist,
                                hasCover = coverVersion.Length > 0,
                                coverVersion,
                                trackVersion = trackVersion.ToString(),
                                positionMs,
                                durationMs,
                                timelineUpdatedAtMs,
                                fetcherUpdatedAtMs = now
                            };

                            lock (_stateLock)
                            {
                                _currentJson = JsonSerializer.Serialize(info);
                            }

                            lastTitle = title;
                            lastArtist = artist;
                            lastSourceApp = sourceApp;
                            lastPlayingState = isPlaying;
                            lastCoverVersion = coverVersion;
                            lastPositionMs = positionMs;
                            lastDurationMs = durationMs;
                            lastPublishedAtMs = now;
                        }
                    }
                    else
                    {
                        bool enteringNoMedia = lastTitle != "NO_MEDIA";
                        if (enteringNoMedia || now - lastPublishedAtMs >= 500)
                        {
                            if (enteringNoMedia) trackVersion++;
                            lock (_stateLock)
                            {
                                _currentJson = JsonSerializer.Serialize(new
                                {
                                    processId = ProcessId,
                                    isPlaying = false,
                                    title = "暂无音乐播放",
                                    artist = "请打开播放软件",
                                    hasCover = false,
                                    coverVersion = "",
                                    trackVersion = trackVersion.ToString(),
                                    positionMs = 0,
                                    durationMs = 0,
                                    timelineUpdatedAtMs = 0,
                                    fetcherUpdatedAtMs = now
                                });
                                _currentCover = Array.Empty<byte>();
                                _currentCoverVersion = "";
                            }
                            lastTitle = "NO_MEDIA";
                            lastArtist = null;
                            lastSourceApp = "";
                            lastCoverVersion = "";
                            lastPositionMs = -1;
                            lastDurationMs = -1;
                            lastPublishedAtMs = now;
                        }
                    }
                }
                catch (Exception ex)
                {
                    LogSmtcFailure(ex);
                    _manager = null;
                }

                await Task.Delay(100);
            }
        }

        private static async Task HandleFlutterRequest(TcpClient client)
        {
            using (client)
            {
                try
                {
                    client.ReceiveTimeout = 1000;
                    client.SendTimeout = 1000;
                    NetworkStream stream = client.GetStream();
                    using var reader = new StreamReader(
                        stream,
                        Encoding.ASCII,
                        detectEncodingFromByteOrderMarks: false,
                        bufferSize: 1024,
                        leaveOpen: true
                    );

                    string? requestLine = await reader.ReadLineAsync()
                        .WaitAsync(TimeSpan.FromSeconds(1));
                    if (string.IsNullOrWhiteSpace(requestLine)) return;
                    bool headersComplete = false;
                    for (int headerCount = 0; headerCount < 64; headerCount++)
                    {
                        string? header = await reader.ReadLineAsync()
                            .WaitAsync(TimeSpan.FromSeconds(1));
                        if (string.IsNullOrEmpty(header))
                        {
                            headersComplete = true;
                            break;
                        }
                    }
                    if (!headersComplete) return;

                    string[] requestParts = requestLine.Split(' ', 3, StringSplitOptions.RemoveEmptyEntries);
                    if (requestParts.Length < 2) return;
                    string method = requestParts[0].ToUpperInvariant();
                    Uri uri = new Uri("http://127.0.0.1" + requestParts[1]);
                    string path = uri.AbsolutePath.ToLowerInvariant();

                    if (method == "OPTIONS")
                    {
                        await WriteHttpResponseAsync(stream, 204, null, Array.Empty<byte>());
                        return;
                    }

                    if (path == "/info")
                    {
                        string json;
                        lock (_stateLock) json = _currentJson;
                        await WriteHttpResponseAsync(
                            stream,
                            200,
                            "application/json; charset=utf-8",
                            Encoding.UTF8.GetBytes(json)
                        );
                    }
                    else if (path == "/spectrum")
                    {
                        bool available = _spectrumAnalyzer.TryActivate();
                        var snapshot = _spectrumAnalyzer.GetSnapshot();
                        byte[] buffer = JsonSerializer.SerializeToUtf8Bytes(new
                        {
                            levels = snapshot.Levels,
                            updatedAtMs = snapshot.UpdatedAtMs,
                            available = available || snapshot.Available,
                            error = snapshot.Error,
                            rms = snapshot.Rms,
                            sampleFrames = snapshot.SampleFrames,
                            format = snapshot.Format
                        });
                        await WriteHttpResponseAsync(
                            stream,
                            200,
                            "application/json; charset=utf-8",
                            buffer
                        );
                    }
                    else if (path == "/cover")
                    {
                        byte[] cover;
                        string version;
                        lock (_stateLock)
                        {
                            cover = (byte[])_currentCover.Clone();
                            version = _currentCoverVersion;
                        }

                        if (cover.Length == 0 || version.Length == 0)
                        {
                            await WriteHttpResponseAsync(stream, 404, null, Array.Empty<byte>());
                        }
                        else if (QueryValue(uri, "version") == version)
                        {
                            await WriteHttpResponseAsync(stream, 304, null, Array.Empty<byte>());
                        }
                        else
                        {
                            await WriteHttpResponseAsync(
                                stream,
                                200,
                                "image/jpeg",
                                cover,
                                version
                            );
                        }
                    }
                    else if (path == "/command")
                    {
                        string? cmd = QueryValue(uri, "cmd");
                        var session = _manager?.GetCurrentSession();
                        if (session != null && !string.IsNullOrEmpty(cmd))
                        {
                            if (cmd == "TOGGLE") await session.TryTogglePlayPauseAsync();
                            else if (cmd == "NEXT") await session.TrySkipNextAsync();
                            else if (cmd == "PREV") await session.TrySkipPreviousAsync();
                        }
                        await WriteHttpResponseAsync(stream, 200, null, Array.Empty<byte>());
                    }
                    else
                    {
                        await WriteHttpResponseAsync(stream, 404, null, Array.Empty<byte>());
                    }
                }
                catch { }
            }
        }

        private static string? QueryValue(Uri uri, string key)
        {
            string query = uri.Query.TrimStart('?');
            foreach (string item in query.Split('&', StringSplitOptions.RemoveEmptyEntries))
            {
                string[] pair = item.Split('=', 2);
                string name = Uri.UnescapeDataString(pair[0].Replace('+', ' '));
                if (!string.Equals(name, key, StringComparison.OrdinalIgnoreCase)) continue;
                return pair.Length > 1
                    ? Uri.UnescapeDataString(pair[1].Replace('+', ' '))
                    : string.Empty;
            }
            return null;
        }

        private static async Task WriteHttpResponseAsync(
            NetworkStream stream,
            int statusCode,
            string? contentType,
            byte[] body,
            string? etag = null
        )
        {
            string reason = statusCode switch
            {
                200 => "OK",
                204 => "No Content",
                304 => "Not Modified",
                404 => "Not Found",
                _ => "OK"
            };
            var header = new StringBuilder()
                .Append($"HTTP/1.1 {statusCode} {reason}\r\n")
                .Append("Access-Control-Allow-Origin: *\r\n")
                .Append("Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n")
                .Append("Connection: close\r\n")
                .Append($"Content-Length: {body.Length}\r\n");
            if (!string.IsNullOrEmpty(contentType)) header.Append($"Content-Type: {contentType}\r\n");
            if (!string.IsNullOrEmpty(etag)) header.Append($"ETag: {etag}\r\n");
            header.Append("\r\n");

            byte[] headerBytes = Encoding.ASCII.GetBytes(header.ToString());
            await stream.WriteAsync(headerBytes, 0, headerBytes.Length)
                .WaitAsync(TimeSpan.FromSeconds(1));
            if (body.Length > 0)
            {
                await stream.WriteAsync(body, 0, body.Length)
                    .WaitAsync(TimeSpan.FromSeconds(1));
            }
        }
    }
}
