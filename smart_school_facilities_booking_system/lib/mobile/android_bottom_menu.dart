import 'package:flutter/material.dart';

class BottomMenuBar extends StatelessWidget {

  final double height;
  final int currentIndex;
  final Function(int) onTabSelected;

  //---------------------------------------
// the 3 value must be pass into it
//---------------------------------------
  BottomMenuBar({
    required this.height,
    required this.currentIndex,
    required this.onTabSelected,
  });

  //---------------------------------------
// icon for different index
//---------------------------------------

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

//---------------------------------------
// index and current index
//--------------------------------------

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
          //---------------------------------------
// ontab mean the index is selected
//---------------------------------------
        onPressed: () {
            onTabSelected(index); // tell parent which icon was tapped
          },
          icon: Icon(iconForIndex(index), size: 24, color: c),
        ),
      ),
    );
  }
//---------------------------------------
// main build
//---------------------------------------

  @override
  Widget build(BuildContext context) {
    //---------------------------------------
// circle size adn rise
//---------------------------------------
    const double bubbleSize = 48;
    const double rise = 17;

    return LayoutBuilder(
      builder: (context, constraints) {
// w = constraints.maxWidth = total width of the bar.
        double w = constraints.maxWidth;
// slot = w / 5 = split the bar into 5 equal lanes (one per tab).
        double slot = w / 5;
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

        double top = (height / 2) - (bubbleSize / 2) - rise;


        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none, // allow circle + glow to go outside a bit
            children: [
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

//---------------------------------------
// orange circle and animation
//---------------------------------------
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
//---------------------------------------
// orange circle
//---------------------------------------
                      Container(
                        width: bubbleSize,
                        height: bubbleSize,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6F6F), // orange/pink
                          shape: BoxShape.circle,
                          boxShadow: [
//---------------------------------------
// make glow with shadow
//---------------------------------------
                            BoxShadow(
                              color: const Color(0xFFFF6F6F).withOpacity(0.35),
                              blurRadius: 24, // bigger = blurrier
                              spreadRadius: 10,
                            ),
//---------------------------------------
// inner glow
//---------------------------------------
                            BoxShadow(
                              color: const Color(0xFFFF6F6F).withOpacity(0.25),
                              blurRadius: 12,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                      ),

//---------------------------------------
// icon for index
//---------------------------------------
                      Icon(
                        iconForIndex(currentIndex),
                        size: 24,
                        color: Colors.black,
                      ),
                    ],
                  ),
                ),
              ),

//---------------------------------------
// icon possition
//---------------------------------------
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
