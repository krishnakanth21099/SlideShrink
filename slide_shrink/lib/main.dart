import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_compress/video_compress.dart';

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
      });
    }
  }

  Future<void> compressVideo() async {
    if (inputPath == null) return;

    setState(() {
      isCompressing = true;
    });

    try {
      final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        inputPath!,
        quality: _selectedQuality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: _targetFrameRate, // Apply the custom frame rate
      );

      if (mediaInfo != null && mediaInfo.file != null) {
        setState(() {
          outputPath = mediaInfo.file!.path;
          compressedSize = mediaInfo.file!.lengthSync() / (1024 * 1024);
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
      setState(() {
        isCompressing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error during compression: $e')));
    }
  }

  void playVideo() {
    if (outputPath != null) {
      controller = VideoPlayerController.file(File(outputPath!))
        ..initialize().then((_) {
          setState(() {});
          controller!.play();
        });
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
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
                min: 10, // Minimum frame rate
                max: 30, // Maximum frame rate
                divisions: 20, // Number of divisions between min and max
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
              ElevatedButton(
                onPressed: playVideo,
                child: Text('Preview Compressed Video'),
              ),
              if (controller != null && controller!.value.isInitialized) ...[
                AspectRatio(
                  aspectRatio: controller!.value.aspectRatio,
                  child: VideoPlayer(controller!),
                ),
              ]
            ]
          ],
        ),
      ),
    );
  }
}
