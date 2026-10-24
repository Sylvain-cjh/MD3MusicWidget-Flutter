import 'dart:io';



HttpClient directLyricsHttpClient([HttpClient? client]) =>
    (client ?? HttpClient())..findProxy = (_) => 'DIRECT';
