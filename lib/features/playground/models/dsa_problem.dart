import 'package:flutter/material.dart';
class DsaProblem {
  final String id;
  final String title;
  final String description;
  final String difficulty;
  final List<Map<String, dynamic>> examples;
  final String constraints;
  final List<Map<String, dynamic>> testCases;
  final List<String> topics;
  final String? solution;

  DsaProblem({
    required this.id,
    required this.title,
    required this.description,
    required this.difficulty,
    required this.examples,
    required this.constraints,
    required this.testCases,
    this.topics = const [],
    this.solution,
  });

  factory DsaProblem.fromJson(Map<String, dynamic> json) {
    return DsaProblem(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: (json['description'] ?? '').toString().replaceAll('\\n', '\n'),
      difficulty: json['difficulty'] ?? 'easy',
      examples: List<Map<String, dynamic>>.from(
        (json['examples'] ?? []).map((e) => Map<String, dynamic>.from(e)),
      ),
      constraints: (json['constraints'] ?? '').toString().replaceAll('\\n', '\n'),
      testCases: List<Map<String, dynamic>>.from(
        (json['test_cases'] ?? []).map((e) => Map<String, dynamic>.from(e)),
      ),
      topics: List<String>.from(json['topics'] ?? []),
      solution: json['solution'] != null
          ? json['solution'].toString().replaceAll('\\n', '\n')
          : null,
    );
  }

  Color get difficultyColor {
    switch (difficulty) {
      case 'easy': return const Color(0xFF00B8A3);
      case 'medium': return const Color(0xFFFFB800);
      case 'hard': return const Color(0xFFFF375F);
      default: return Colors.grey;
    }
  }
}