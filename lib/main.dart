import 'package:flutter/material.dart';
import 'repositories/notebook_repository.dart';
import 'repositories/scene_storage.dart';
import 'state/notebook_controller.dart';
import 'ui/screens/notebook_home_screen.dart';

void main() {
  runApp(const LibreBilliardApp());
}

class LibreBilliardApp extends StatefulWidget {
  final NotebookController? controller;
  final NotebookRepository? repository;
  final SceneStorage? sceneStorage;
  final bool autoInitializeRepository;

  const LibreBilliardApp({
    super.key,
    this.controller,
    this.repository,
    this.sceneStorage,
    this.autoInitializeRepository = true,
  });

  @override
  State<LibreBilliardApp> createState() => _LibreBilliardAppState();
}

class _LibreBilliardAppState extends State<LibreBilliardApp> {
  late final NotebookController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        NotebookController(repository: widget.repository);
    if (_ownsController && widget.autoInitializeRepository) {
      _controller.initialize();
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LibreBilliard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F4C75),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: NotebookHomeScreen(
        controller: _controller,
        sceneStorage: widget.sceneStorage,
      ),
    );
  }
}
