import 'package:flutter/material.dart';
import '../application/notebook_controller.dart';
import 'library_screen.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({
    super.key,
    required this.controller,
    this.embedded = false,
  });
  final NotebookController controller;
  final bool embedded;
  @override
  Widget build(BuildContext context) =>
      LibraryScreen(controller: controller, embedded: embedded);
}
