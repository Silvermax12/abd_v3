import 'package:flutter/material.dart';

class DisclaimerDialog extends StatelessWidget {
  final VoidCallback onAccept;

  const DisclaimerDialog({super.key, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
          SizedBox(width: 12),
          Text('Important Notice'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Educational & Demo Use Only',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This application is provided for educational and demonstration purposes only.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Key Points:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildBulletPoint(
                '• You are solely responsible for how you use this tool'),
            _buildBulletPoint(
                '• Respect copyright laws and content creators\' rights'),
            _buildBulletPoint('• Download only content you have rights to access'),
            _buildBulletPoint('• The developers assume no liability for misuse'),
            const SizedBox(height: 12),
            const Text(
              'By continuing, you acknowledge that you understand and agree to use this application responsibly and legally.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            // Exit app
            Navigator.of(context).pop();
            Future.delayed(const Duration(milliseconds: 100), () {
              // This would ideally close the app, but we'll just keep the dialog
            });
          },
          child: const Text('Decline'),
        ),
        ElevatedButton(
          onPressed: onAccept,
          child: const Text('I Understand & Accept'),
        ),
      ],
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

