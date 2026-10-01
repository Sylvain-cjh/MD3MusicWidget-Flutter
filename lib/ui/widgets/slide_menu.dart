import 'package:flutter/material.dart';
import '../../core/app_state.dart';

class SlideMenu extends StatelessWidget {
  final Animation<double> animation;
  final String menuSide;
  final VoidCallback onSettingsTap;
  final VoidCallback onExitTap;

  const SlideMenu({
    super.key,
    required this.animation,
    required this.menuSide,
    required this.onSettingsTap,
    required this.onExitTap,
  });

  @override
  Widget build(BuildContext context) {
    final offsetBegin = MediaQuery.disableAnimationsOf(context)
        ? Offset.zero
        : menuSide == "left"
        ? const Offset(0.2, 0)
        : const Offset(-0.2, 0);

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: offsetBegin,
          end: Offset.zero,
        ).animate(animation.drive(CurveTween(curve: Curves.easeOutCubic))),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: IntrinsicWidth(
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppState.currentScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppState.currentScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
                
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMenuItem(
                    Icons.settings_rounded,
                    "偏好设置中心",
                    onSettingsTap,
                  ),
                  const SizedBox(height: 2),
                  _buildMenuItem(
                    Icons.power_settings_new_rounded,
                    "完全退出组件",
                    onExitTap,
                    isError: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    IconData icon,
    String label,
    VoidCallback onClick, {
    bool isError = false,
  }) {
    final color = isError
        ? AppState.currentScheme.error
        : AppState.currentScheme.onSurface;
    return InkWell(
      onTap: onClick,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
