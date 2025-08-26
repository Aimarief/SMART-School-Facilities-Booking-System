// android_bottom_menu.dart
// Bottom bar with 5 icons in one straight line (always black).
// The SELECTED icon is drawn ON TOP inside a bigger orange circle.
// The circle + icon move UP together a bit, and the circle has a blurry glow.

import 'package:flutter/material.dart';

class BottomMenuBar extends StatelessWidget {
  // height = total height of the bar
  final double height;

  // currentIndex = selected tab (0..4)
  final int currentIndex;

  // onTabSelected = callback when user taps an icon
  final Function(int) onTabSelected;

  BottomMenuBar({
    required this.height,
    required this.currentIndex,
    required this.onTabSelected,
  });

  // iconForIndex() = choose icon for each slot (0..4)
  IconData iconForIndex(int i) {
    if (i == 0) {
      return Icons.calendar_today;
    } else if (i == 1) {
      return Icons.list_alt;
    } else if (i == 2) {
      return Icons.add;
    } else if (i == 3) {
      return Icons.notifications_none;
    } else {
      return Icons.account_circle;
    }
  }

  // _rowIcon() = one icon inside the baseline row
  // If this is the selected index, we draw it TRANSPARENT to keep spacing.
  Widget _rowIcon({
    required int index,
    required int current,
  }) {
    Color c;
    if (current == index) {
      c = Colors.transparent; // hide but keep space so layout never jumps
    } else {
      c = Colors.black;       // always black for normal icons
    }

    return Expanded(
      child: Center(
        child: IconButton(
          onPressed: () {
            onTabSelected(index); // tell parent which icon was tapped
          },
          icon: Icon(iconForIndex(index), size: 24, color: c),
          tooltip: '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // You can tweak these 2 numbers to your taste
    const double bubbleSize = 48; // circle size (bigger = more visible)
    const double rise = 17;       // how high the circle+icon move UP (px)

    return LayoutBuilder(
      builder: (context, constraints) {
        // w  = full width of the bar
        // slot = width for each of the 5 equal positions
        double w = constraints.maxWidth;
        double slot = w / 5;

        // left = x position so the circle centers under the selected slot
        double left;
        if (currentIndex == 0) {
          left = (slot * 0) + (slot / 2) - (bubbleSize / 2);
        } else if (currentIndex == 1) {
          left = (slot * 1) + (slot / 2) - (bubbleSize / 2);
        } else if (currentIndex == 2) {
          left = (slot * 2) + (slot / 2) - (bubbleSize / 2);
        } else if (currentIndex == 3) {
          left = (slot * 3) + (slot / 2) - (bubbleSize / 2);
        } else {
          left = (slot * 4) + (slot / 2) - (bubbleSize / 2);
        }

        // top = vertical position:
        // start at vertical center of the bar, then move UP by "rise"
        double top = (height / 2) - (bubbleSize / 2) - rise;

        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none, // allow circle + glow to go outside a bit
            children: [
              // 1) Purple background with rounded top corners
              Container(
                height: height,
                decoration: const BoxDecoration(
                  color: Color(0xFF9747FF),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
              ),

              // 2) ORANGE CIRCLE + GLOW + BLACK ICON (selected) — move together
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                top: top,
                left: left,
                child: SizedBox(
                  width: bubbleSize,
                  height: bubbleSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // orange circle with a soft blurry glow around it
                      Container(
                        width: bubbleSize,
                        height: bubbleSize,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6F6F), // orange/pink
                          shape: BoxShape.circle,
                          boxShadow: [
                            // outer soft glow (bigger blur)
                            BoxShadow(
                              color: const Color(0xFFFF6F6F).withOpacity(0.35),
                              blurRadius: 24, // bigger = blurrier
                              spreadRadius: 10,
                            ),
                            // inner glow for more punch
                            BoxShadow(
                              color: const Color(0xFFFF6F6F).withOpacity(0.25),
                              blurRadius: 12,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                      ),

                      // selected icon centered on top (keep it black)
                      Icon(
                        iconForIndex(currentIndex),
                        size: 24,
                        color: Colors.black,
                      ),
                    ],
                  ),
                ),
              ),

              // 3) ICON ROW (always on the same baseline, never shifts)
              Positioned.fill(
                child: Row(
                  children: [
                    _rowIcon(index: 0, current: currentIndex),
                    _rowIcon(index: 1, current: currentIndex),
                    _rowIcon(index: 2, current: currentIndex),
                    _rowIcon(index: 3, current: currentIndex),
                    _rowIcon(index: 4, current: currentIndex),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
