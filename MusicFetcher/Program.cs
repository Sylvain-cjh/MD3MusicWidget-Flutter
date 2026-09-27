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
        private const int MediaCapabilities = 0xFF;
        private const byte PreviousCommand = 1;
        private const byte TogglePlayPauseCommand = 2;
        private const byte NextCommand = 3;
        private static readonly int ProcessId = Environment.ProcessId;
        private static byte[] _currentInfoBytes = JsonSerializer.SerializeToUtf8Bytes(new
        {
            processId = ProcessId,
            sourceAppId = "",
            isPlaying = false,
            isShuffleActive = (bool?)null,
            autoRepeatMode = "",
            title = "暂无音乐播放",
            artist = "请打开播放软件",
            hasCover = false,
            coverVersion = "",
            trackVersion = "",
            positionMs = 0,
            durationMs = 0,
            timelineUpdatedAtMs = 0,
            fetcherUpdatedAtMs = 0,
            capabilities = MediaCapabilities
        });
        private static byte[] _currentCover = Array.Empty<byte>();
        private static string _currentCoverVersion = "";
        private static readonly object _stateLock = new();
        private static string _selectedSourceAppId = "";
        private static readonly SpectrumAnalyzer _spectrumAnalyzer = new();
        private static GlobalSystemMediaTransportControlsSessionManager? _manager;
        private static GlobalSystemMediaTransportControlsSession? _observedSession;
        private static StreamHub? _streamHub;
        private static readonly SemaphoreSlim _smtcWake = new(0, 1);
        private static long _mediaPropertiesRevision = 1;
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
                var manager = await AwaitWinRtAsync(
                    GlobalSystemMediaTransportControlsSessionManager.RequestAsync(),
                    TimeSpan.FromSeconds(2)
                );
                manager.CurrentSessionChanged += OnCurrentSessionChanged;
                manager.SessionsChanged += OnSessionsChanged;
                _manager = manager;
                return _manager != null;
            }
            catch (Exception ex)
            {
                LogSmtcFailure(ex);
                _manager = null;
                return false;
            }
        }

        private static void WakeSmtc(bool mediaPropertiesChanged)
        {
            if (mediaPropertiesChanged) Interlocked.Increment(ref _mediaPropertiesRevision);
            if (_smtcWake.CurrentCount == 0)
            {
                try { _smtcWake.Release(); } catch (SemaphoreFullException) { }
            }
        }

        private static void OnCurrentSessionChanged(
            GlobalSystemMediaTransportControlsSessionManager sender,
            CurrentSessionChangedEventArgs args
        ) => WakeSmtc(mediaPropertiesChanged: true);

        private static void OnSessionsChanged(
            GlobalSystemMediaTransportControlsSessionManager sender,
            SessionsChangedEventArgs args
        ) => WakeSmtc(mediaPropertiesChanged: true);

        private static void OnMediaPropertiesChanged(
            GlobalSystemMediaTransportControlsSession sender,
            MediaPropertiesChangedEventArgs args
        ) => WakeSmtc(mediaPropertiesChanged: true);

        private static void OnPlaybackInfoChanged(
            GlobalSystemMediaTransportControlsSession sender,
            PlaybackInfoChangedEventArgs args
        ) => WakeSmtc(mediaPropertiesChanged: false);

        private static void OnTimelinePropertiesChanged(
            GlobalSystemMediaTransportControlsSession sender,
            TimelinePropertiesChangedEventArgs args
        ) => WakeSmtc(mediaPropertiesChanged: false);

        private static void ObserveSession(GlobalSystemMediaTransportControlsSession? session)
        {
            if (ReferenceEquals(_observedSession, session)) return;
            if (_observedSession != null)
            {
                _observedSession.MediaPropertiesChanged -= OnMediaPropertiesChanged;
                _observedSession.PlaybackInfoChanged -= OnPlaybackInfoChanged;
                _observedSession.TimelinePropertiesChanged -= OnTimelinePropertiesChanged;
            }
            _observedSession = session;
            if (session != null)
            {
                session.MediaPropertiesChanged += OnMediaPropertiesChanged;
                session.PlaybackInfoChanged += OnPlaybackInfoChanged;
                session.TimelinePropertiesChanged += OnTimelinePropertiesChanged;
            }
            Interlocked.Increment(ref _mediaPropertiesRevision);
        }

        static async Task Main(string[] args)
        {
            Console.WriteLine("=========================================");
            Console.WriteLine("🚀 [SMTC Base64 融合内核] 已经启动...");
            Console.WriteLine("=========================================\n");

            try
            {
                _streamHub = new StreamHub(
                    GetCurrentInfoBytes,
                    GetCurrentArtwork,
                    () =>
                    {
                        bool available = _spectrumAnalyzer.TryActivate();
                        return _spectrumAnalyzer.GetCompactSnapshot(available);
                    },
                    ExecuteMediaCommandAsync
                );
                _streamHub.Start();

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

        private static byte[] GetCurrentInfoBytes()
        {
            lock (_stateLock) return _currentInfoBytes;
        }

        private static (string Version, byte[] Bytes) GetCurrentArtwork()
        {
            lock (_stateLock)
                return (_currentCoverVersion, (byte[])_currentCover.Clone());
        }

        private static GlobalSystemMediaTransportControlsSession? SelectSession()
        {
            var manager = _manager;
            if (manager == null) return null;
            string selectedSource;
            lock (_stateLock) selectedSource = _selectedSourceAppId;
            if (selectedSource.Length == 0) return manager.GetCurrentSession();

            GlobalSystemMediaTransportControlsSession? pausedMatch = null;
            foreach (var session in manager.GetSessions())
            {
                if (!string.Equals(session.SourceAppUserModelId, selectedSource,
                    StringComparison.OrdinalIgnoreCase)) continue;
                pausedMatch ??= session;
                try
                {
                    if (session.GetPlaybackInfo().PlaybackStatus ==
                        GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing)
                        return session;
                }
                catch { }
            }
            return pausedMatch;
        }

        private static byte[] GetSourcesJson()
        {
            string selectedSource;
            lock (_stateLock) selectedSource = _selectedSourceAppId;
            var sources = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            if (_manager != null)
            {
                foreach (var session in _manager.GetSessions())
                {
                    string id = session.SourceAppUserModelId ?? "";
                    if (id.Length == 0) continue;
                    bool playing = false;
                    try
                    {
                        playing = session.GetPlaybackInfo().PlaybackStatus ==
                            GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
                    }
                    catch { }
                    sources[id] = sources.GetValueOrDefault(id) || playing;
                }
            }
            return JsonSerializer.SerializeToUtf8Bytes(new
            {
                selectedSourceAppId = selectedSource,
                sources = sources.OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
                    .Select(pair => new { sourceAppId = pair.Key, isPlaying = pair.Value })
            });
        }

        private static async Task ExecuteMediaCommandAsync(byte command)
        {
            var session = SelectSession();
            if (session == null) return;
            if (command == TogglePlayPauseCommand)
                await session.TryTogglePlayPauseAsync();
            else if (command == NextCommand)
                await session.TrySkipNextAsync();
            else if (command == PreviousCommand)
                await session.TrySkipPreviousAsync();
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
            int nextPollDelayMs = 650;
            GlobalSystemMediaTransportControlsSessionMediaProperties? cachedProperties = null;
            long cachedPropertiesRevision = -1;

            while (true)
            {
                try
                {
                    if (!await EnsureMediaManagerAsync())
                    {
                        await Task.Delay(400);
                        continue;
                    }
                    var session = SelectSession();
                    long now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                    if (session != null)
                    {
                        ObserveSession(session);
                        long mediaRevision = Interlocked.Read(ref _mediaPropertiesRevision);
                        if (cachedProperties == null || cachedPropertiesRevision != mediaRevision)
                        {
                            cachedProperties = await AwaitWinRtAsync(
                                session.TryGetMediaPropertiesAsync(),
                                MediaPropertiesTimeout
                            );
                            cachedPropertiesRevision = mediaRevision;
                        }
                        var props = cachedProperties;
                        var playback = session.GetPlaybackInfo();

                        bool isPlaying = playback.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
                        nextPollDelayMs = isPlaying ? 1000 : 2000;
                        string title = props.Title ?? "未知歌曲";
                        string artist = props.Artist ?? "未知歌手";
                        string sourceApp = session.SourceAppUserModelId ?? "";
                        string selectedSource;
                        lock (_stateLock) selectedSource = _selectedSourceAppId;
                        _spectrumAnalyzer.SetTargetApplication(sourceApp, isPlaying,
                            selectedSource.Length > 0);
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
                                sourceAppId = sourceApp,
                                isPlaying,
                                isShuffleActive = playback.IsShuffleActive,
                                autoRepeatMode = playback.AutoRepeatMode?.ToString().ToLowerInvariant() ?? "",
                                title,
                                artist,
                                hasCover = coverVersion.Length > 0,
                                coverVersion,
                                trackVersion = trackVersion.ToString(),
                                positionMs,
                                durationMs,
                                timelineUpdatedAtMs,
                                fetcherUpdatedAtMs = now,
                                capabilities = MediaCapabilities
                            };

                            byte[] infoBytes = JsonSerializer.SerializeToUtf8Bytes(info);
                            lock (_stateLock) _currentInfoBytes = infoBytes;
                            _streamHub?.PublishInfo(infoBytes);
                            if (coverVersion != lastCoverVersion && coverVersion.Length > 0)
                            {
                                var artwork = GetCurrentArtwork();
                                if (artwork.Version == coverVersion && artwork.Bytes.Length > 0)
                                    _streamHub?.PublishArtwork(artwork.Version, artwork.Bytes);
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
                        ObserveSession(null);
                        cachedProperties = null;
                        cachedPropertiesRevision = -1;
                        _spectrumAnalyzer.SetTargetApplication("", false, false);
                        nextPollDelayMs = 2500;
                        bool enteringNoMedia = lastTitle != "NO_MEDIA";
                        if (enteringNoMedia || now - lastPublishedAtMs >= 500)
                        {
                            if (enteringNoMedia) trackVersion++;
                            byte[] infoBytes = JsonSerializer.SerializeToUtf8Bytes(new
                            {
                                processId = ProcessId,
                                sourceAppId = "",
                                isPlaying = false,
                                isShuffleActive = (bool?)null,
                                autoRepeatMode = "",
                                title = "暂无音乐播放",
                                artist = "请打开播放软件",
                                hasCover = false,
                                coverVersion = "",
                                trackVersion = trackVersion.ToString(),
                                positionMs = 0,
                                durationMs = 0,
                                timelineUpdatedAtMs = 0,
                                fetcherUpdatedAtMs = now,
                                capabilities = MediaCapabilities
                            });
                            lock (_stateLock)
                            {
                                _currentInfoBytes = infoBytes;
                                _currentCover = Array.Empty<byte>();
                                _currentCoverVersion = "";
                            }
                            _streamHub?.PublishInfo(infoBytes);
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
                    ObserveSession(null);
                    cachedProperties = null;
                    cachedPropertiesRevision = -1;
                    _manager = null;
                    nextPollDelayMs = 650;
                }

                await _smtcWake.WaitAsync(nextPollDelayMs);
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
                    bool browserOrigin = false;
                    for (int headerCount = 0; headerCount < 64; headerCount++)
                    {
                        string? header = await reader.ReadLineAsync()
                            .WaitAsync(TimeSpan.FromSeconds(1));
                        if (string.IsNullOrEmpty(header))
                        {
                            headersComplete = true;
                            break;
                        }
                        if (header.StartsWith("Origin:", StringComparison.OrdinalIgnoreCase))
                            browserOrigin = true;
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
                        byte[] infoBytes;
                        lock (_stateLock) infoBytes = _currentInfoBytes;
                        await WriteHttpResponseAsync(
                            stream,
                            200,
                            "application/json; charset=utf-8",
                            infoBytes
                        );
                    }
                    else if (path == "/sources" && method == "GET")
                    {
                        if (browserOrigin)
                        {
                            await WriteHttpResponseAsync(stream, 403, null,
                                Array.Empty<byte>(), allowCors: false);
                            return;
                        }
                        await WriteHttpResponseAsync(stream, 200,
                            "application/json; charset=utf-8", GetSourcesJson(),
                            allowCors: false);
                    }
                    else if (path == "/source" && method == "POST")
                    {
                        if (browserOrigin)
                        {
                            await WriteHttpResponseAsync(stream, 403, null,
                                Array.Empty<byte>(), allowCors: false);
                            return;
                        }
                        string sourceId = QueryValue(uri, "appId") ?? "";
                        if (sourceId.Length > 512)
                        {
                            await WriteHttpResponseAsync(stream, 400, null,
                                Array.Empty<byte>(), allowCors: false);
                            return;
                        }
                        lock (_stateLock) _selectedSourceAppId = sourceId;
                        WakeSmtc(mediaPropertiesChanged: true);
                        await WriteHttpResponseAsync(stream, 204, null,
                            Array.Empty<byte>(), allowCors: false);
                    }
                    else if (path == "/spectrum.bin")
                    {
                        bool available = _spectrumAnalyzer.TryActivate();
                        byte[] buffer = _spectrumAnalyzer.GetCompactSnapshot(available);
                        await WriteHttpResponseAsync(
                            stream,
                            200,
                            "application/octet-stream",
                            buffer
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
                            format = snapshot.Format,
                            captureMode = snapshot.CaptureMode,
                            targetProcessId = snapshot.TargetProcessId
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
                        if (cmd == "TOGGLE") await ExecuteMediaCommandAsync(TogglePlayPauseCommand);
                        else if (cmd == "NEXT") await ExecuteMediaCommandAsync(NextCommand);
                        else if (cmd == "PREV") await ExecuteMediaCommandAsync(PreviousCommand);
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
            string? etag = null,
            bool allowCors = true
        )
        {
            string reason = statusCode switch
            {
                200 => "OK",
                204 => "No Content",
                304 => "Not Modified",
                400 => "Bad Request",
                403 => "Forbidden",
                404 => "Not Found",
                _ => "OK"
            };
            var header = new StringBuilder()
                .Append($"HTTP/1.1 {statusCode} {reason}\r\n")
                .Append("Connection: close\r\n")
                .Append($"Content-Length: {body.Length}\r\n");
            if (allowCors)
            {
                header.Append("Access-Control-Allow-Origin: *\r\n");
                header.Append("Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n");
            }
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
