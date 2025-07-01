import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_compress/video_compress.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(VideoCompressorApp());
}

class VideoCompressorApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Compressor',
      home: VideoCompressorPage(),
    );
  }
}

class VideoCompressorPage extends StatefulWidget {
  @override
  _VideoCompressorPageState createState() => _VideoCompressorPageState();
}

class _VideoCompressorPageState extends State<VideoCompressorPage> {
  String? inputPath;
  String? outputPath;
  double? originalSize;
  double? compressedSize;
  VideoPlayerController? controller;
  Duration? compressionDuration; // To store the time taken for compression

  bool isCompressing = false;

  // Compression Settings - Customize here
  VideoQuality _selectedQuality = VideoQuality.Res640x480Quality; // Default to Medium
  int _targetFrameRate = 24; // You can adjust this for more compression (e.g., 15, 20, 24, 30)

  Future<void> pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null && result.files.single.path != null) {
      setState(() {
        inputPath = result.files.single.path;
        outputPath = null;
        originalSize = File(inputPath!).lengthSync() / (1024 * 1024);
        compressedSize = null;
        compressionDuration = null; // Reset duration
        // Dispose previous controller if a new video is picked
        controller?.dispose();
        controller = null;
      });
    }
  }

  Future<void> compressVideo() async {
    if (inputPath == null) return;

    setState(() {
      isCompressing = true;
      compressionDuration = null; // Clear previous duration
    });

    final stopwatch = Stopwatch()..start(); // Start the timer

    try {
      final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        inputPath!,
        quality: _selectedQuality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: _targetFrameRate,
      );

      stopwatch.stop(); // Stop the timer

      if (mediaInfo != null && mediaInfo.file != null) {
        setState(() {
          outputPath = mediaInfo.file!.path;
          compressedSize = mediaInfo.file!.lengthSync() / (1024 * 1024);
          compressionDuration = stopwatch.elapsed; // Store elapsed time
          isCompressing = false;
        });
        playVideo();
      } else {
        setState(() {
          isCompressing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compression Failed')));
      }
    } catch (e) {
      stopwatch.stop(); // Ensure stopwatch stops even on error
      setState(() {
        isCompressing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error during compression: $e')));
    }
  }

  void playVideo() {
    if (outputPath != null) {
      controller?.dispose();
      controller = VideoPlayerController.file(File(outputPath!))
        ..initialize().then((_) {
          setState(() {});
          controller!.play();
        });
    }
  }

  Future<void> _saveVideoToGallery() async {
    if (outputPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No compressed video to save.')));
      return;
    }

    // Request storage permission
    // For Android 10 (API 29) and above, WRITE_EXTERNAL_STORAGE is deprecated.
    // gallery_saver_plus uses MediaStore for newer Android versions.
    // For older Android versions, or if you need broader access, Permission.storage is still relevant.
    // For iOS, NSPhotoLibraryAddUsageDescription and NSPhotoLibraryUsageDescription are needed in Info.plist.
    PermissionStatus status = await Permission.photos.request(); // Request photos permission for modern Android/iOS

    if (status.isGranted) {
      try {
        bool? success = await GallerySaver.saveVideo(outputPath!, albumName: "Compressed Videos");
        if (success == true) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Video saved to gallery!')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save video to gallery.')));
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving video: $e')));
      }
    } else if (status.isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Permission denied. Please grant access to save video.')));
    } else if (status.isPermanentlyDenied) {
      // User has permanently denied, guide them to app settings
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Storage permission permanently denied. Please enable it in app settings.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () {
              openAppSettings(); // Opens app settings for the user
            },
          ),
        ),
      );
    } else if (status.isRestricted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Storage permission restricted.')));
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    VideoCompress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Video Compressor')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: pickVideo,
              child: Text('Pick Video'),
            ),
            if (inputPath != null) ...[
              SizedBox(height: 10),
              Text('Original Size: ${originalSize?.toStringAsFixed(2)} MB'),
              SizedBox(height: 10),
              DropdownButton<VideoQuality>(
                value: _selectedQuality,
                onChanged: (VideoQuality? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedQuality = newValue;
                    });
                  }
                },
                items: VideoQuality.values.map<DropdownMenuItem<VideoQuality>>((VideoQuality quality) {
                  return DropdownMenuItem<VideoQuality>(
                    value: quality,
                    child: Text(quality.toString().split('.').last),
                  );
                }).toList(),
              ),
              SizedBox(height: 10),
              Text('Target Frame Rate: $_targetFrameRate FPS'),
              Slider(
                value: _targetFrameRate.toDouble(),
                min: 10,
                max: 30,
                divisions: 20,
                label: _targetFrameRate.round().toString(),
                onChanged: (double value) {
                  setState(() {
                    _targetFrameRate = value.round();
                  });
                },
              ),
              ElevatedButton(
                onPressed: isCompressing ? null : compressVideo,
                child: Text('Compress Video'),
              ),
            ],
            if (isCompressing) ...[
              SizedBox(height: 10),
              CircularProgressIndicator(),
              Text('Compressing...')
            ],
            if (outputPath != null && !isCompressing) ...[
              SizedBox(height: 10),
              Text('Compressed Size: ${compressedSize?.toStringAsFixed(2)} MB'),
              if (compressionDuration != null) // Display compression time
                Text('Compression Time: ${compressionDuration!.inSeconds} seconds'),
              ElevatedButton(
                onPressed: playVideo,
                child: Text('Preview Compressed Video'),
              ),
              if (controller != null && controller!.value.isInitialized) ...[
                AspectRatio(
                  aspectRatio: controller!.value.aspectRatio,
                  child: VideoPlayer(controller!),
                ),
                SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _saveVideoToGallery,
                  child: Text('Save Video to Gallery'),
                ),
              ]
            ]
          ],
        ),
      ),
    );
  }
}
