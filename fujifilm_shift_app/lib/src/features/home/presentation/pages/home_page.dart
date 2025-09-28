import "package:flutter/material.dart";
import "package:flutter_staggered_animations/flutter_staggered_animations.dart";

import "../widgets/camera_connection_card.dart";
import "../widgets/feature_card.dart";
import "../widgets/quick_action_card.dart";
import "../widgets/welcome_header.dart";

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverAppBar(
              floating: true,
              snap: true,
              title: Text('Fujifilm Shift'),
              actions: [
                IconButton(
                  icon: Icon(Icons.settings_outlined),
                  onPressed: _navigateToSettings,
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Welcome header
                  AnimationConfiguration.synchronized(
                    child: const FadeInAnimation(
                      duration: Duration(milliseconds: 600),
                      child: WelcomeHeader(),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Quick actions
                  AnimationConfiguration.synchronized(
                    child: FadeInAnimation(
                      duration: const Duration(milliseconds: 600),
                      delay: const Duration(milliseconds: 100),
                      child: const QuickActionCard(),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Feature cards
                  AnimationConfiguration.synchronized(
                    child: FadeInAnimation(
                      duration: const Duration(milliseconds: 600),
                      delay: const Duration(milliseconds: 200),
                      child: const FeatureCard(),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Camera connection status
                  AnimationConfiguration.synchronized(
                    child: FadeInAnimation(
                      duration: const Duration(milliseconds: 600),
                      delay: const Duration(milliseconds: 300),
                      child: const CameraConnectionCard(),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startPixelShift,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 0,
        label: const Text('Start Capture'),
        icon: const Icon(Icons.camera_alt_outlined),
      ),
    );

  void _navigateToSettings() {
    Navigator.pushNamed(context, "/settings");
  }

  void _startPixelShift() {
    // TODO: Implement pixel shift capture flow
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Pixel shift capture will be implemented next!"),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
