// lib/web/web_tnc.dart
// -----------------------------------------------------------------------------
// WEB TERMS & CONDITIONS / PRIVACY POLICY (Admin)
// - AppBar: WebCustomTopBar with 24-hour clock (same as other admin pages).
// - Body: Single centered card (~70% screen width) with two toggle buttons
//   (T&C / Privacy Policy). Content area shows the text for the selected tab.
// - Edit flow: Press "Edit" -> multiline TextField -> "Save" writes to
//   Firestore collection 'SystemInformation', docs 'TNC' or 'PrivacyPolicy',
//   field 'content'.
// - Beginner-friendly: setState + StreamBuilder + showDialog, ScreenUtil sizing.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'web_top_bar.dart'; // uses WebCustomTopBar like your other web pages

class WebTNC extends StatefulWidget {
  const WebTNC({Key? key}) : super(key: key);

  @override
  State<WebTNC> createState() => _WebTNCState();
}

class _WebTNCState extends State<WebTNC> {
  // ---------------- basic states ----------------
  final bool _use24HourFormat = true; // top bar time format
  String _tab = 'TNC';                // current tab: 'TNC' or 'PrivacyPolicy'
  bool _isEditing = false;            // are we editing?

  // controller for editing content
  final TextEditingController _contentCtrl = TextEditingController();

  // Firestore helpers
  CollectionReference<Map<String, dynamic>> _sysCol() {
    // action: return the collection reference
    return FirebaseFirestore.instance.collection('SystemInformation');
  }

  DocumentReference<Map<String, dynamic>> _docRef() {
    // action: choose document by current tab
    if (_tab == 'TNC') {
      return _sysCol().doc('TNC');
    } else {
      return _sysCol().doc('PrivacyPolicy');
    }
  }

  // ---------------- build ----------------
  @override
  Widget build(BuildContext context) {
    final double contentMaxWidth = 0.7.sw; // ~70% of screen width

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: WebCustomTopBar(use24HourFormat: _use24HourFormat),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: 16.h),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: _buildMainCard(),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- main card ----------------
  Widget _buildMainCard() {
    return Card(
      color: const Color(0xFFEDDFFF), // your box color
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToggleRow(),
            SizedBox(height: 10.h),
            Divider(height: 1.h, thickness: 1),
            SizedBox(height: 12.h),
            _buildContentArea(),
          ],
        ),
      ),
    );
  }

  // ---------------- toggle buttons (match login hover style) ----------------
  Widget _buildToggleRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _HoverToggleButton(
          text: 'T&C',
          isSelected: _tab == 'TNC',
          onTap: () {
            setState(() {
              _tab = 'TNC';
              _isEditing = false; // exit edit mode when switching
            });
          },
        ),
        SizedBox(width: 12.w),
        _HoverToggleButton(
          text: 'Privacy Policy',
          isSelected: _tab == 'PrivacyPolicy',
          onTap: () {
            setState(() {
              _tab = 'PrivacyPolicy';
              _isEditing = false; // exit edit mode when switching
            });
          },
        ),
      ],
    );
  }

  // ---------------- content viewer / editor ----------------
  Widget _buildContentArea() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _docRef().snapshots(),
      builder: (context, snapshot) {
        // read current content safely
        String content = '';
        if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
          final Map<String, dynamic>? m = snapshot.data!.data();
          if (m != null && m.containsKey('content') && m['content'] != null) {
            content = m['content'].toString();
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // header row: title left, edit/save right
            Row(
              children: [
                Expanded(
                  child: Text(
                    _tab == 'TNC' ? 'Terms & Conditions' : 'Privacy Policy',
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
                  ),
                ),
                if (_isEditing == false)
                  ElevatedButton.icon(
                    onPressed: () {
                      // load current content into controller and enter edit mode
                      _contentCtrl.text = content;
                      setState(() { _isEditing = true; });
                    },
                    icon: Icon(Icons.edit, size: 16.sp),
                    label: Text('Edit', style: TextStyle(fontSize: 13.sp)),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () {
                          // cancel editing
                          setState(() { _isEditing = false; });
                        },
                        child: Text('Cancel', style: TextStyle(fontSize: 13.sp)),
                      ),
                      SizedBox(width: 6.w),
                      ElevatedButton(
                        onPressed: () async {
                          await _saveContent(_contentCtrl.text.trim());
                        },
                        child: Text('Save', style: TextStyle(fontSize: 13.sp)),
                      ),
                    ],
                  ),
              ],
            ),

            SizedBox(height: 10.h),

            // content body
            if (_isEditing == false)
              Container(
                width: double.infinity,
                constraints: BoxConstraints(minHeight: 160.h),
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: Colors.black12),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    content.isEmpty ? '(No content yet)' : content,
                    style: TextStyle(fontSize: 14.sp),
                  ),
                ),
              )
            else
              TextField(
                controller: _contentCtrl,
                maxLines: 20,
                minLines: 10,
                decoration: InputDecoration(
                  isDense: false,
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                  hintText: 'Enter content...',
                  contentPadding: EdgeInsets.all(12.w),
                  filled: true, // make background white in edit mode
                  fillColor: Colors.white,
                ),
                style: TextStyle(fontSize: 14.sp),
              ),
          ],
        );
      },
    );
  }

  // ---------------- save to Firestore ----------------
  Future<void> _saveContent(String text) async {
    try {
      await _docRef().set({'content': text}, SetOptions(merge: true)); // write field
      setState(() { _isEditing = false; }); // exit edit

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved successfully', style: TextStyle(fontSize: 13.sp))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save. Please try again.', style: TextStyle(fontSize: 13.sp))),
        );
      }
    }
  }

  // ---------------- dispose ----------------
  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }
}

// ---------------- CUSTOM TOGGLE BUTTON (login-style) ------------------------
class _HoverToggleButton extends StatefulWidget {
  final String text;         // label
  final bool isSelected;     // selected?
  final VoidCallback onTap;  // tap handler

  const _HoverToggleButton({
    Key? key,
    required this.text,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_HoverToggleButton> createState() => _HoverToggleButtonState();
}

class _HoverToggleButtonState extends State<_HoverToggleButton> {
  bool _isHovered = false; // hover state for web

  @override
  Widget build(BuildContext context) {
    // colors copied from WebLoginPage HoverToggleButton
    const Color basePurple = Color(0xFF6E00D4);
    const Color hoverPurple = Color(0xFF7A1AE4);

    final Color bgColor = widget.isSelected
        ? Colors.white
        : (_isHovered ? hoverPurple : basePurple);
    final Color textColor = widget.isSelected ? basePurple : Colors.white;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 150.w,
          height: 40.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: basePurple, width: 1.w),
          ),
          child: Text(
            widget.text,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
