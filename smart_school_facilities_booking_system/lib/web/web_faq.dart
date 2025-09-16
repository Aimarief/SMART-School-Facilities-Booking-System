// lib/web/web_faq.dart
// -----------------------------------------------------------------------------
// WEB FAQ PAGE (Admin-managed FAQ list)
// - Uses your same WebCustomTopBar with 24-hour clock (like rating page).
// - Single centered card (~70% of screen width) that contains:
//     * Search bar + "Add" button (top)
//     * Divider
//     * List of FAQ titles with View/Edit actions
// - Add/Edit popups (title + description). Data saved to Firestore collection "FAQ".
// - Delete has a square-corner confirmation dialog with red Delete button (#FF0707).
//
// FYP CODING STYLE (BEGINNER FRIENDLY):
// * Simple setState + StreamBuilder + showDialog.
// * Comment every function and important actions.
// * Use ScreenUtil: .w .h .sp .sw .sh to scale (Samsung A32 + Web zoom safe).
// * Wrap long areas in SingleChildScrollView to avoid overflow on zoom.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'web_top_bar.dart'; // uses WebCustomTopBar like your rating page

class WebFAQ extends StatefulWidget {
  const WebFAQ({Key? key}) : super(key: key);

  @override
  State<WebFAQ> createState() => _WebFAQState();
}

class _WebFAQState extends State<WebFAQ> {
  // --- Firestore reference to read/write the "FAQ" collection ---
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- top bar format flag (24h) ---
  final bool _use24HourFormat = true;

  // --- search controller + in-memory keyword ---
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchKeyword = '';

  // --------------------------- FIRESTORE HELPERS ----------------------------
  // Return the typed reference to collection 'FAQ'.
  CollectionReference<Map<String, dynamic>> _faqCol() {
    return _firestore.collection('FAQ');
  }

  // ------------------------------- BUILD ------------------------------------
  // Build the full page with a top bar and one centered card box.
  @override
  Widget build(BuildContext context) {
    final double contentMaxWidth = 0.7.sw; // ~70% of screen width (scales)

    return Scaffold(
      // --- your common web top bar with 24h clock ---
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: WebCustomTopBar(use24HourFormat: _use24HourFormat),
      ),

      // --- body wrapped in a scroll view to avoid overflow on zoom ---
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: 16.h),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMainCard(), // the single center card (search + add + list)
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------ MAIN CARD (SEARCH + LIST) -----------------------
  // One card that contains the search + add row and the list below it.
  Widget _buildMainCard() {
    return Card(
      color: const Color(0xFFEDDFFF), // changed box color
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- header row: search field + add button ---
            LayoutBuilder(
              builder: (context, constraints) {
                return Wrap(
                  spacing: 12.w,
                  runSpacing: 12.h,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // search takes remaining width, falls to full width if narrow
                    SizedBox(
                      width: (constraints.maxWidth - 12.w - 120.w) > 240.w
                          ? constraints.maxWidth - 12.w - 120.w
                          : constraints.maxWidth,
                      child: _buildSearchField(),
                    ),
                    SizedBox(width: 108.w, child: _buildAddButton()),
                  ],
                );
              },
            ),

            SizedBox(height: 12.h),
            Divider(height: 1.h, thickness: 1),
            SizedBox(height: 12.h),

            // --- list area: stream + in-memory filter by title ---
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _faqCol().orderBy('updatedAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Center(
                      child: SizedBox(
                        width: 24.w,
                        height: 24.w,
                        child: const CircularProgressIndicator(),
                      ),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Text(
                      'Failed to load FAQ. Please try again.',
                      style: TextStyle(fontSize: 14.sp, color: Colors.red),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                final List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered = docs
                    .where((d) {
                  final title = (d.data()['title'] ?? '').toString().toLowerCase();
                  if (_searchKeyword.isEmpty) return true; // no filter when empty
                  return title.contains(_searchKeyword);
                })
                    .toList();

                if (filtered.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Text(
                      'No FAQ found. Try another keyword or add a new one.',
                      style: TextStyle(fontSize: 14.sp),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => SizedBox(height: 8.h),
                  itemBuilder: (context, index) {
                    final doc = filtered[index];
                    final data = doc.data();
                    final String title = (data['title'] ?? '').toString();

                    return Container(
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title.isEmpty ? '(No title)' : title,
                              style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Wrap(
                            spacing: 8.w,
                            runSpacing: 4.h,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () {
                                  _openViewDialog(
                                    title: data['title']?.toString() ?? '',
                                    description: data['description']?.toString() ?? '',
                                  );
                                },
                                icon: Icon(Icons.visibility, size: 16.sp),
                                label: Text('View', style: TextStyle(fontSize: 13.sp)),
                              ),
                              ElevatedButton.icon(
                                onPressed: () {
                                  _openEditDialog(doc.id, data);
                                },
                                icon: Icon(Icons.edit, size: 16.sp),
                                label: Text('Edit', style: TextStyle(fontSize: 13.sp)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------ SEARCH FIELD (TOP) ------------------------------
  // Simple text field that updates _searchKeyword in-memory for local filter.
  Widget _buildSearchField() {
    return TextField(
      controller: _searchCtrl, // connect controller to field
      onChanged: (value) {
        setState(() {
          _searchKeyword = value.trim().toLowerCase(); // update keyword
        });
      },
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
        labelText: 'Search FAQ title',
        labelStyle: TextStyle(fontSize: 14.sp),
        prefixIcon: Icon(Icons.search, size: 20.sp),
      ),
      style: TextStyle(fontSize: 14.sp),
    );
  }

  // --------------------------- ADD BUTTON ----------------------------------
  // Opens the Add dialog to create a new FAQ item.
  Widget _buildAddButton() {
    return SizedBox(
      height: 40.h,
      child: ElevatedButton.icon(
        onPressed: () {
          _openAddDialog(); // open add form
        },
        icon: Icon(Icons.add, size: 18.sp),
        label: Text('Add', style: TextStyle(fontSize: 14.sp)),
      ),
    );
  }

  // ------------------------------ ADD DIALOG --------------------------------
  // Pop-up form to add new FAQ (title + description) and save to Firestore.
  Future<void> _openAddDialog() async {
    final TextEditingController titleCtrl = TextEditingController();
    final TextEditingController descCtrl = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
          title: Text('Add FAQ', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 480.w,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle: TextStyle(fontSize: 14.sp),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: TextStyle(fontSize: 14.sp),
                ),
                SizedBox(height: 12.h),
                TextField(
                  controller: descCtrl,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    labelStyle: TextStyle(fontSize: 14.sp),
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  style: TextStyle(fontSize: 14.sp),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // close without saving
              },
              child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
            ),
            ElevatedButton(
              onPressed: () async {
                final String t = titleCtrl.text.trim();
                final String d = descCtrl.text.trim();

                if (t.isEmpty || d.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Title and description cannot be empty.', style: TextStyle(fontSize: 13.sp))),
                  );
                  return;
                }

                try {
                  final now = DateTime.now();
                  await _faqCol().add({
                    'title': t,
                    'description': d,
                    'titleLower': t.toLowerCase(),
                    'createdAt': now,
                    'updatedAt': now,
                  });

                  if (mounted) Navigator.of(context).pop(); // close dialog
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('FAQ added.', style: TextStyle(fontSize: 13.sp))),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to save FAQ. Please try again.', style: TextStyle(fontSize: 13.sp))),
                  );
                }
              },
              child: Text('Save', style: TextStyle(fontSize: 14.sp)),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------ EDIT DIALOG -------------------------------
  // Pop-up to edit or delete an existing FAQ.
  Future<void> _openEditDialog(String docId, Map<String, dynamic> data) async {
    final TextEditingController titleCtrl = TextEditingController(text: data['title']?.toString() ?? '');
    final TextEditingController descCtrl = TextEditingController(text: data['description']?.toString() ?? '');

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
          title: Text('Edit FAQ', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 520.w,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle: TextStyle(fontSize: 14.sp),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: TextStyle(fontSize: 14.sp),
                ),
                SizedBox(height: 12.h),
                TextField(
                  controller: descCtrl,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    labelStyle: TextStyle(fontSize: 14.sp),
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  style: TextStyle(fontSize: 14.sp),
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            // --- LEFT: Delete ---
            TextButton(
              onPressed: () async {
                final bool? ok = await _confirmDelete();
                if (ok == true) {
                  try {
                    await _faqCol().doc(docId).delete();
                    if (mounted) Navigator.of(context).pop();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('FAQ deleted.', style: TextStyle(fontSize: 13.sp))),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to delete FAQ. Please try again.', style: TextStyle(fontSize: 13.sp))),
                    );
                  }
                }
              },
              child: Text('Delete', style: TextStyle(fontSize: 14.sp, color: Colors.red)),
            ),

            // --- RIGHT: Cancel + Save ---
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // close without saving
                  },
                  child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final String t = titleCtrl.text.trim();
                    final String d = descCtrl.text.trim();
                    if (t.isEmpty || d.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Title and description cannot be empty.', style: TextStyle(fontSize: 13.sp))),
                      );
                      return;
                    }

                    try {
                      final now = DateTime.now();
                      await _faqCol().doc(docId).update({
                        'title': t,
                        'description': d,
                        'titleLower': t.toLowerCase(),
                        'updatedAt': now,
                      });

                      if (mounted) Navigator.of(context).pop();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('FAQ updated.', style: TextStyle(fontSize: 13.sp))),
                        );
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to update FAQ. Please try again.', style: TextStyle(fontSize: 13.sp))),
                      );
                    }
                  },
                  child: Text('Save', style: TextStyle(fontSize: 14.sp)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // ------------------------------- VIEW DIALOG ------------------------------
  // Read-only dialog to show title + description.
  Future<void> _openViewDialog({required String title, required String description}) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
          title: Text(title.isEmpty ? '(No title)' : title,
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 560.w,
            child: SingleChildScrollView(
              child: Text(
                description.isEmpty ? '(No description)' : description,
                style: TextStyle(fontSize: 14.sp),
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // close dialog
              },
              child: Text('Close', style: TextStyle(fontSize: 14.sp)),
            ),
          ],
        );
      },
    );
  }

  // -------------------------- DELETE CONFIRMATION ---------------------------
  // Square-corner confirmation dialog (barrierDismissible=false) for delete.
  Future<bool?> _confirmDelete() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(0)),
          ),
          title: Text('Delete FAQ?', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          content: Text(
            'Are you sure you want to delete this FAQ? This cannot be undone.',
            style: TextStyle(fontSize: 14.sp),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // user cancels
              },
              child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true); // user confirms
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(const Color(0xFFFF0707)),
                foregroundColor: WidgetStateProperty.all(Colors.white),
              ),
              child: Text('Delete', style: TextStyle(fontSize: 14.sp)),
            ),
          ],
        );
      },
    );
  }

  // -------------------------------- DISPOSE ---------------------------------
  // Dispose controllers to free memory when leaving the page.
  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
