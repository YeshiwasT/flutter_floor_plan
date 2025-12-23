import 'web_download_helper.dart';

/// Stub implementation for non-web platforms
class WebDownloadHelperStub implements WebDownloadHelper {
  @override
  Future<void> downloadSVG(String svgContent, String filename) async {
    throw UnimplementedError('SVG download not supported on this platform');
  }
}

/// Function to create WebDownloadHelper - stub version
WebDownloadHelper createWebDownloadHelper() => WebDownloadHelperStub();

