import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_compress/video_compress.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
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
  Duration? compressionDuration;
  VlcPlayerController? vlcController;

  bool isCompressing = false;
  bool isUploading = false;
  String? uploadedVideoId;
  String? hlsUrl;
  String? videoUrl;

  // Compression Settings - Customize here
  VideoQuality _selectedQuality =
      VideoQuality.Res640x480Quality; // Default to Medium
  int _targetFrameRate =
      24; // You can adjust this for more compression (e.g., 15, 20, 24, 30)

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
        // playVideo();
        uploadVideo(); // Upload to server after compression
      } else {
        setState(() {
          isCompressing = false;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Compression Failed')));
      }
    } catch (e) {
      stopwatch.stop(); // Ensure stopwatch stops even on error
      setState(() {
        isCompressing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during compression: $e')));
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

  Future<void> uploadVideo() async {
    if (outputPath == null) return;

    setState(() {
      isUploading = true;
    });

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://e2e-77-175.ssdcloudindia.net/dev/content/video_upload/'),
      );

      request.headers.addAll({
        'Accept': 'application/json',
      });

      request.files.add(
        await http.MultipartFile.fromPath(
          'video_file',
          outputPath!,
        ),
      );

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var jsonResponse = json.decode(responseData);

      if (response.statusCode == 201 || response.statusCode == 200) {
        setState(() {
          uploadedVideoId = jsonResponse['id'];
          hlsUrl = jsonResponse['hls_url'];
          videoUrl = jsonResponse['file_url'];
          isUploading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video uploaded successfully!')),
        );

        getVideoInfo(); // Get updated video info with HLS URL
      } else {
        setState(() {
          isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: ${response.statusCode}')),
        );
      }
    } catch (e) {
      setState(() {
        isUploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload error: $e')),
      );
    }
  }

  Future<void> getVideoInfo() async {
    if (uploadedVideoId == null) return;

    try {
      var response = await http.get(
        Uri.parse('https://e2e-77-175.ssdcloudindia.net/dev/content/videos/$uploadedVideoId/'),
        headers: {
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        var jsonResponse = json.decode(response.body);
        setState(() {
          hlsUrl = jsonResponse['hls_url'];
          videoUrl = jsonResponse['file_url'];
        });
      }
    } catch (e) {
      print('Error getting video info: $e');
    }
  }

  Future<void> _saveVideoToGallery() async {
    if (outputPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No compressed video to save.')));
      return;
    }

    PermissionStatus status = await Permission.photos.request();

    if (status.isGranted) {
      try {
        final result = await ImageGallerySaver.saveFile(outputPath!);
        if (result != null && result['isSuccess'] == true) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Video saved to gallery!')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to save video to gallery.')));
        }
      } catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving video: $e')));
      }
    } else if (status.isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Permission denied. Please grant access to save video.')));
    } else if (status.isPermanentlyDenied) {
      // User has permanently denied, guide them to app settings
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Storage permission permanently denied. Please enable it in app settings.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () {
              openAppSettings(); // Opens app settings for the user
            },
          ),
        ),
      );
    } else if (status.isRestricted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Storage permission restricted.')));
    }
  }

  void playHlsVideo() {
    if (hlsUrl != null) {
      // If controller already exists and video has ended, reset it
      if (vlcController != null && vlcController!.value.isEnded) {
        vlcController!.stop().then((_) {
          vlcController!.setMediaFromNetwork(hlsUrl!);
          vlcController!.play();
        });
      }
      // If controller doesn't exist or needs to be recreated
      else if (vlcController == null || !vlcController!.value.isInitialized) {
        vlcController?.dispose();
        vlcController = VlcPlayerController.network(
          hlsUrl!,
          hwAcc: HwAcc.auto,
          autoPlay: false,
          options: VlcPlayerOptions(),
        )..addListener(() {
            setState(() {});
            // Handle video end - enable replay
            if (vlcController!.value.isEnded) {
              setState(() {});
            }
          });
        setState(() {});
      } else {
        // Controller exists and is ready, just play
        vlcController!.play();
      }
    }
  }

  void togglePlayPause() {
    if (vlcController == null) return;

    // If video has ended, restart it
    if (vlcController!.value.isEnded) {
      vlcController!.stop().then((_) {
        vlcController!.setMediaFromNetwork(hlsUrl!);
        vlcController!.play();
      });
    }
    // Otherwise, toggle play/pause normally
    else if (vlcController!.value.isPlaying) {
      vlcController!.pause();
    } else {
      vlcController!.play();
    }
  }

  void seekTo(double value) {
    final duration = vlcController?.value.duration;
    if (duration != null) {
      final seekPosition = Duration(milliseconds: (duration.inMilliseconds * value).round());
      vlcController?.seekTo(seekPosition);
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    vlcController?.dispose();
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
                items: VideoQuality.values.map<DropdownMenuItem<VideoQuality>>(
                    (VideoQuality quality) {
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
              // ElevatedButton(
              //   onPressed: _saveVideoToGallery,
              //   child: Text('Save Video to Gallery'),
              // ),
            ],
            if (isUploading) ...[
              SizedBox(height: 10),
              CircularProgressIndicator(),
              Text('Uploading to server...')
            ],
            if (uploadedVideoId != null && !isUploading) ...[
              SizedBox(height: 10),
              Text('Video uploaded successfully!'),
              Text('Video ID: $uploadedVideoId'),
              if (hlsUrl != null) ...[
                SizedBox(height: 10),
                Text('HLS URL: $hlsUrl'),
                Text('Compressed Size: ${compressedSize?.toStringAsFixed(2)} MB'),
                ElevatedButton(
                  onPressed: playHlsVideo,
                  child: Text('Stream Video (HLS)'),
                ),
              ],
              if (vlcController != null) ...[
                SizedBox(height: 10),
                // Container(
                  // constraints: BoxConstraints(
                  //   maxHeight: MediaQuery.of(context).size.height * 0.6, // Max 60% of screen height
                  //   maxWidth: MediaQuery.of(context).size.width * 0.9,   // Max 90% of screen width
                  // ),
                AspectRatio(
                    aspectRatio: vlcController!.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VlcPlayer(
                          controller: vlcController!,
                          aspectRatio: vlcController!.value.aspectRatio,
                          placeholder: Center(child: CircularProgressIndicator()),
                        ),
                        // Play/Pause overlay button
                        GestureDetector(
                          onTap: togglePlayPause,
                          child: Container(
                            color: Colors.transparent,
                            width: double.infinity,
                            height: double.infinity,
                            child: Center(
                              child: AnimatedOpacity(
                                opacity: (vlcController!.value.isPlaying) ? 0.0 : 1.0,
                                duration: Duration(milliseconds: 300),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    // Show replay icon if video has ended
                                    vlcController!.value.isEnded 
                                      ? Icons.replay 
                                      : vlcController!.value.isPlaying 
                                        ? Icons.pause 
                                        : Icons.play_arrow,
                                    color: Colors.white,
                                    size: 60,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // ),
                // Video Progress Bar
                if (vlcController!.value.duration != null && 
                    vlcController!.value.duration.inMilliseconds > 0) ...[
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    color: Colors.black54,
                    child: Column(
                      children: [
                        Slider(
                          value: () {
                            final position = vlcController!.value.position.inMilliseconds;
                            final duration = vlcController!.value.duration.inMilliseconds;
                            if (duration > 0 && position.isFinite) {
                              return (position / duration).clamp(0.0, 1.0);
                            }
                            return 0.0;
                          }(),
                          onChanged: (value) => seekTo(value),
                          activeColor: Colors.blue,
                          inactiveColor: Colors.grey,
                        ),
                        // Time Display
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${vlcController!.value.position.inMinutes}:${(vlcController!.value.position.inSeconds % 60).toString().padLeft(2, '0')}',
                                style: TextStyle(color: Colors.white),
                              ),
                              Text(
                                '${vlcController!.value.duration.inMinutes}:${(vlcController!.value.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ]
            ],
            // if (outputPath != null && !isCompressing && uploadedVideoId == null) ...[
            //   SizedBox(height: 10),
            //   Text('Compressed Size: ${compressedSize?.toStringAsFixed(2)} MB'),
            //   if (compressionDuration != null) // Display compression time
            //     Text(
            //         'Compression Time: ${compressionDuration!.inSeconds} seconds'),
            //   ElevatedButton(
            //     onPressed: playVideo,
            //     child: Text('Preview Compressed Video'),
            //   ),
            //   if (controller != null && controller!.value.isInitialized) ...[
            //     GestureDetector(
            //       onTap: () {
            //         setState(() {
            //           controller!.value.isPlaying
            //               ? controller!.pause()
            //               : controller!.play();
            //         });
            //       },
            //       child: AspectRatio(
            //         aspectRatio: controller!.value.aspectRatio,
            //         child: Stack(
            //           alignment: Alignment.center,
            //           children: [
            //             VideoPlayer(controller!),
            //             if (!controller!.value.isPlaying)
            //               Container(
            //                 decoration: BoxDecoration(
            //                   color: Colors.black26,
            //                   shape: BoxShape.circle,
            //                 ),
            //                 child: Icon(
            //                   Icons.play_arrow,
            //                   color: Colors.white,
            //                   size: 50,
            //                 ),
            //               ),
            //           ],
            //         ),
            //       ),
            //     ),
            //     VideoProgressIndicator(
            //       controller!,
            //       allowScrubbing: true,
            //       padding: EdgeInsets.symmetric(vertical: 8),
            //     ),
            //     ValueListenableBuilder(
            //       valueListenable: controller!,
            //       builder: (context, VideoPlayerValue value, child) {
            //         return Row(
            //           mainAxisAlignment: MainAxisAlignment.spaceBetween,
            //           children: [
            //             Text(
            //               '${value.position.inMinutes}:${(value.position.inSeconds % 60).toString().padLeft(2, '0')}',
            //             ),
            //             Text(
            //               '${value.duration.inMinutes}:${(value.duration.inSeconds % 60).toString().padLeft(2, '0')}',
            //             ),
            //           ],
            //         );
            //       },
            //     ),
            //     SizedBox(height: 10),
            //   ]
            // ]
          ],
        ),
      ),
    );
  }
}
