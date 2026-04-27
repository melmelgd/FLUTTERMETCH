import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.textMain,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Privacy Policy for Event Management',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textMain),
            ),
            const SizedBox(height: 16),
            const Text(
              'Last Updated: April 27, 2026',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            _buildSection(
              '1. Information We Collect',
              'We collect information that you provide directly to us when you use our attendance and event management system, such as names, IDs, and attendance timestamps.',
            ),
            _buildSection(
              '2. How We Use Information',
              'The information collected is used solely for managing event attendance, verifying participants, and generating reports for the LGU Ormoc City.',
            ),
            _buildSection(
              '3. Data Storage',
              'Your data is stored locally on your device and synced with our secure servers when an internet connection is available.',
            ),
            _buildSection(
              '4. Data Security',
              'We implement industry-standard security measures to protect your data from unauthorized access or disclosure.',
            ),
            _buildSection(
              '5. Contact Us',
              'If you have any questions about this Privacy Policy, please contact the IT Department of LGU Ormoc.',
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5)),
        ],
      ),
    );
  }
}
