import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'style.dart';

const _description = [
  "Run Laps counts track laps with your phone's GPS. Pick a lane and a distance, press Start, and run. No account required.",
  "I like running, and I like my knees quiet. So I run at the track. It's peaceful right up until lap forty-something of a half marathon, when I look down and discover I've reset the counter. I'd love to say I only did that once.",
  "Run Laps uses the length of the lane you're in. It shows average lap time, speed, and projected finish as you go. You have to hold Stop for three seconds. That feature had a very specific customer.",
  'Run Laps is free and open source, built by Dreamers Inc.',
];

class RunLapsAboutPage extends StatelessWidget {
  const RunLapsAboutPage({super.key});

  Future<void> _open(BuildContext context, String url) async {
    try {
      if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Give both platform errors and a refused launch the same fallback.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the link.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, size: 19),
              ),
              Expanded(child: Text('ABOUT', style: mono(12))),
            ],
          ),
          const Divider(color: C.rule, height: 1, indent: 16, endIndent: 16),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 550),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('run laps', style: mono(26, weight: 600)),
                        const SizedBox(height: 16),
                        for (final paragraph in _description)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Text(paragraph, style: mono(14, height: 1.55)),
                          ),
                        TextButton(
                          style: _linkStyle,
                          onPressed: () => _open(context, 'https://github.com/dreamers-laboratory/run-laps'),
                          child: Text('Open source on GitHub', style: mono(13, underline: true)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: C.rule, height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: _linkStyle,
                onPressed: () => _open(context, 'https://thedreamers.us/'),
                child: Text('BUILT BY DREAMERS', style: mono(11, underline: true)),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  static final _linkStyle = TextButton.styleFrom(
    padding: EdgeInsets.zero,
    minimumSize: const Size(0, 44),
    foregroundColor: C.ink,
  );
}
