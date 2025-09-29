import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../widgets/camera_connection_card.dart';
import '../widgets/feature_card.dart';
import '../widgets/quick_action_card.dart';
import '../widgets/welcome_header.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              floating: true,
              snap: true,
              title: const Text("Fujifilm Shift"),
              actions: <Widget>[
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => _navigateToSettings(context),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: SliverList(
                delegate: SliverChildListDelegate(<Widget>[
                  // Welcome header
                  const AnimationConfiguration.synchronized(
                    child: FadeInAnimation(
                      duration: Duration(milliseconds: 600),
                      child: WelcomeHeader(),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Quick actions
                  const AnimationConfiguration.synchronized(
                    child: FadeInAnimation(
                      duration: Duration(milliseconds: 600),
                      delay: Duration(milliseconds: 100),
                      child: QuickActionCard(),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Feature cards
                  const AnimationConfiguration.synchronized(
                    child: FadeInAnimation(
                      duration: Duration(milliseconds: 600),
                      delay: Duration(milliseconds: 200),
                      child: FeatureCard(),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Camera connection status
                  const AnimationConfiguration.synchronized(
                    child: FadeInAnimation(
                      duration: Duration(milliseconds: 600),
                      delay: Duration(milliseconds: 300),
                      child: CameraConnectionCard(),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startPixelShift(context),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 0,
        label: const Text("Start Capture"),
        icon: const Icon(Icons.camera_alt_outlined),
      ),
    );

  void _navigateToSettings(BuildContext context) {
    Navigator.pushNamed(context, '/settings');
  }

  void _startPixelShift(BuildContext context) {
    // TODO: Implement pixel shift capture flow
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pixel shift capture will be implemented next!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
