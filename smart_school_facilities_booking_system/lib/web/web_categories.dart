// lib/web_categories.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'web_top_bar.dart';

/// CategoriesPage
/// - Collection: 'FacilitiesCategory' with fields: name(String), deleted(bool), createdAt(Timestamp)
/// - Soft delete: set deleted = true (only if no active Facilities under this category)
/// - Rename: updates category 'name' and propagates to 'Facilities' docs (field 'categoryName')
/// - Design: purple box layout, scrollable, responsive with .w .h .sp
/// - Only if/else used (no ?: or ??)
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({Key? key}) : super(key: key);

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  // Top bar time format
  final bool _use24HourFormat = true;

  // Left search
  final TextEditingController _searchCtrl = TextEditingController();

  // Selection
  String? _selectedCatId;
  String _selectedCatName = '';

  // Right panel mode (Option A: simple string) → 'view' | 'add' | 'edit'
  String _mode = 'view';

  // Form controllers
  final TextEditingController _newCtrl = TextEditingController();
  final TextEditingController _editCtrl = TextEditingController();

  // ---------- Helpers (no ?:) ----------

  /// Clean string by trimming spaces
  String _clean(String s) {
    return s.trim();
  }

  /// Centralized sizing/styling so View/Edit/Add look identical in size
  /// Matches web_list_manager (labels 12.sp, field text 14.sp, 10.h padding)
  InputDecoration _commonInputDecoration() {
    return InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 15.h), // same height as manager page
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Color(0xFFCBC3FF)),
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFCBC3FF)),
      ),
      disabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFCBC3FF)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFCBC3FF)),
      ),
    );
  }

  /// Check if a category name exists (case-insensitive), optionally ignoring a specific doc id
  Future<bool> _categoryNameExists(String name, {String? ignoreId}) async {
    final String q = name.toLowerCase();
    final snap = await FirebaseFirestore.instance
        .collection('FacilitiesCategory')
        .get();

    bool exists = false;
    int i = 0;
    while (i < snap.docs.length) {
      final d = snap.docs[i];
      final dataAny = d.data();
      Map<String, dynamic> data = <String, dynamic>{};
      if (dataAny is Map<String, dynamic>) {
        data = dataAny;
      }

      bool deleted = false;
      if (data.containsKey('deleted') && data['deleted'] != null) {
        if (data['deleted'] == true) {
          deleted = true;
        } else {
          deleted = false;
        }
      } else {
        deleted = false;
      }

      String nm = '';
      if (data.containsKey('name') && data['name'] != null) {
        nm = data['name'].toString().toLowerCase();
      } else {
        nm = '';
      }

      bool sameId = false;
      if (ignoreId == null) {
        sameId = false;
      } else {
        if (d.id == ignoreId) {
          sameId = true;
        } else {
          sameId = false;
        }
      }

      if (!deleted) {
        if (!sameId) {
          if (nm == q) {
            exists = true;
            i = snap.docs.length; // break
          }
        }
      }
      i = i + 1;
    }
    return exists;
  }

  /// Add a new category (right panel Add -> Confirm)
  Future<void> _addCategory() async {
    final String name = _clean(_newCtrl.text);
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a category name')),
      );
      return;
    }

    if (await _categoryNameExists(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Category "$name" already exists')),
      );
      return;
    }

    try {
      final docRef = await FirebaseFirestore.instance
          .collection('FacilitiesCategory')
          .add({
        'name': name,
        'deleted': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _selectedCatId = docRef.id;
        _selectedCatName = name;
        _mode = 'view';
        _newCtrl.text = '';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category added')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  /// Save edit (right panel Edit -> Confirm)
  Future<void> _saveEdit() async {
    if (_selectedCatId == null) {
      return;
    }

    final String newName = _clean(_editCtrl.text);
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    if (await _categoryNameExists(newName, ignoreId: _selectedCatId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Category "$newName" already exists')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('FacilitiesCategory')
          .doc(_selectedCatId)
          .update({'name': newName});

      await _propagateCategoryNameChange(_selectedCatId!, newName);

      setState(() {
        _selectedCatName = newName;
        _mode = 'view';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category updated')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  /// Update all facilities to reflect renamed category (batch in chunks)
  Future<int> _propagateCategoryNameChange(String catId, String newName) async {
    final db = FirebaseFirestore.instance;

    final snap = await db
        .collection('Facilities')
        .where('categoryId', isEqualTo: catId)
        .where('deleted', isEqualTo: false)
        .get();

    int i = 0;
    while (i < snap.docs.length) {
      int end;
      if (i + 400 < snap.docs.length) {
        end = i + 400;
      } else {
        end = snap.docs.length;
      }

      final batch = db.batch();
      int j = i;
      while (j < end) {
        batch.update(snap.docs[j].reference, {'categoryName': newName});
        j = j + 1;
      }
      await batch.commit();
      i = end;
    }
    return snap.docs.length;
  }

  /// Confirm delete dialog (returns true if Yes)
  /// Confirm delete dialog (same design as logout dialog)
  Future<bool> _confirmDelete() async {
    final bool? res = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // cannot close by tapping outside
      builder: (_) => AlertDialog(
        // square corners
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          'Delete category?',
          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to delete this category?',
          style: TextStyle(fontSize: 14.sp),
        ),
        actions: [
          TextButton(
            onPressed: () { Navigator.of(context).pop(false); },
            child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
          ),
          ElevatedButton(
            onPressed: () { Navigator.of(context).pop(true); },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF0707), // red confirm
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            child: Text('Confirm', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (res == null) {
      return false;
    } else {
      return res;
    }
  }


  /// Soft delete a category (only if no facilities are inside)
  Future<void> _softDelete() async {
    if (_selectedCatId == null) {
      return;
    }

    try {
      final facSnap = await FirebaseFirestore.instance
          .collection('Facilities')
          .where('categoryId', isEqualTo: _selectedCatId)
          .where('deleted', isEqualTo: false)
          .get();

      if (facSnap.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This category still contains facilities. Please delete the facilities first.')),
        );
        return;
      }

      await FirebaseFirestore.instance
          .collection('FacilitiesCategory')
          .doc(_selectedCatId)
          .update({'deleted': true});

      setState(() {
        _selectedCatId = null;
        _selectedCatName = '';
        _mode = 'view';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category deleted')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: WebCustomTopBar(use24HourFormat: _use24HourFormat),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 460.w + 24.w + 1200.w,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // LEFT BOX
                              _Box(
                                width: 460.w,
                                height: 965.h,
                                title: 'Category',
                                header: _SearchHeader(
                                  controller: _searchCtrl,
                                  hint: 'Search',
                                  onChanged: (t) {
                                    // when search typing, refresh list
                                    setState(() {});
                                  },
                                  onAdd: () {
                                    // open add panel
                                    setState(() {
                                      _mode = 'add';
                                      _newCtrl.text = '';
                                    });
                                  },
                                ),
                                child: _buildLeftList(),
                              ),
                              SizedBox(width: 24.w),
                              // RIGHT BOX
                              _Box(
                                width: 1200.w,
                                height: 965.h,
                                title: 'Details',
                                child: Padding(
                                  padding: EdgeInsets.only(right: 8.w, bottom: 8.h),
                                  child: _buildRightPanelChild(),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// LEFT list body (scrollable content placed inside _Box)
  Widget _buildLeftList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('FacilitiesCategory')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;

        final List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered =
        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final String q = _clean(_searchCtrl.text).toLowerCase();

        int i = 0;
        while (i < docs.length) {
          final d = docs[i];
          final data = d.data();

          bool del = false;
          if (data.containsKey('deleted') && data['deleted'] != null) {
            if (data['deleted'] == true) {
              del = true;
            } else {
              del = false;
            }
          } else {
            del = false;
          }

          String nm = '';
          if (data.containsKey('name') && data['name'] != null) {
            nm = data['name'].toString();
          } else {
            nm = '';
          }

          bool matches;
          if (q.isEmpty) {
            matches = true;
          } else {
            final String cmp = nm.toLowerCase();
            if (cmp.contains(q)) {
              matches = true;
            } else {
              matches = false;
            }
          }

          if (!del) {
            if (matches) {
              filtered.add(d);
            }
          }
          i = i + 1;
        }

        if (filtered.isEmpty) {
          return _EmptyCenter(text: 'No categories found');
        }

        return ListView.separated(
          itemCount: filtered.length,
          physics: const AlwaysScrollableScrollPhysics(),
          separatorBuilder: (_, __) => SizedBox(height: 8.h),
          itemBuilder: (context, index) {
            final d = filtered[index];
            final m = d.data();

            String nm = '';
            if (m.containsKey('name') && m['name'] != null) {
              nm = m['name'].toString();
            } else {
              nm = '';
            }

            return _ListTileCard(
              label: nm,
              onTap: () {
                // select item and go to view mode
                setState(() {
                  _selectedCatId = d.id;
                  _selectedCatName = nm;
                  _mode = 'view';
                });
              },
            );
          },
        );
      },
    );
  }

  /// RIGHT panel content selector (Add / View / Edit / Idle)
  Widget _buildRightPanelChild() {
    if (_mode == 'add') {
      return _panelAdd();
    } else {
      if (_selectedCatId == null) {
        return SizedBox(
          height: 820.h,
          child: Center(
            child: Text('Please select a category', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
          ),
        );
      } else {
        if (_mode == 'edit') {
          return _panelEdit();
        } else {
          return _panelView();
        }
      }
    }
  }

  // ---------- Panels (same size fields across modes, matching manager/facilities design) ----------

  /// Add panel
  Widget _panelAdd() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 6.h),
        Text('Add Category', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        SizedBox(height: 10.h),

        Text('Name', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
        SizedBox(height: 6.h),
        TextFormField(
          controller: _newCtrl,
          style: TextStyle(fontSize: 15.sp),
          decoration: _commonInputDecoration(),
        ),
        SizedBox(height: 14.h),

        Row(
          children: [
            ElevatedButton(
              onPressed: _addCategory,
              child: const Text('Confirm'),
            ),
            SizedBox(width: 10.w),
            OutlinedButton(
              onPressed: () {
                // cancel add → go back to view (no selection change)
                setState(() {
                  _mode = 'view';
                });
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }

  /// View (read-only) panel
  Widget _panelView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 6.h),
        Text('Details', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        SizedBox(height: 10.h),

        Text('Name', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
        SizedBox(height: 6.h),
        // Read-only field — transparent fill like web_facilities
        TextFormField(
          key: ValueKey<String>('view|name|$_selectedCatName'),
          initialValue: _selectedCatName,
          enabled: false,
          style: TextStyle(fontSize: 17.sp),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        SizedBox(height: 14.h),

        // Buttons: Edit + Close (no Delete here)
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () {
                // Close: clear selection like facilities "Close"
                setState(() {
                  _selectedCatId = null;
                  _selectedCatName = '';
                  _mode = 'view';
                });
              },
              child: const Text('Close'),
            ),
            SizedBox(width: 8.w),
            ElevatedButton(
              onPressed: () {
                // go to edit mode and preload text
                setState(() {
                  _mode = 'edit';
                  _editCtrl.text = _selectedCatName;
                });
              },
              child: const Text('Edit'),
            ),
          ],
        ),
      ],
    );
  }

  /// Edit panel
  Widget _panelEdit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 6.h),
        Text('Edit Category', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        SizedBox(height: 10.h),

        Text('Name', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
        SizedBox(height: 6.h),
        // Editable field (same sizing/styling as add)
        TextFormField(
          controller: _editCtrl,
          style: TextStyle(fontSize: 17.sp),
          decoration: _commonInputDecoration(),
        ),
        SizedBox(height: 14.h),

        // Buttons aligned right: Delete · Cancel · Confirm (same as facilities)
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () async {
                final bool sure = await _confirmDelete();
                if (sure) {
                  await _softDelete();
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
            SizedBox(width: 8.w),
            TextButton(
              onPressed: () {
                // cancel edit → back to view
                setState(() {
                  _mode = 'view';
                });
              },
              child: const Text('Cancel'),
            ),
            SizedBox(width: 8.w),
            ElevatedButton(
              onPressed: _saveEdit,
              child: const Text('Confirm'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _newCtrl.dispose();
    _editCtrl.dispose();
    super.dispose();
  }
}

// ================== Reusable widgets (design-matched) ==================

class _Box extends StatelessWidget {
  const _Box({
    Key? key,
    required this.width,
    required this.height,
    required this.title,
    required this.child,
    this.header,
  }) : super(key: key);

  final double width;
  final double height;
  final String title;
  final Widget child;
  final Widget? header;

  static const Color _fill = Color(0xFFEDDFFF);    // light purple background
  static const Color _outline = Color(0xFF8620E2); // purple border line

  @override
  Widget build(BuildContext context) {
    final List<Widget> head = <Widget>[];
    if (header != null) {
      head.add(header!);
      head.add(SizedBox(height: 8.h));
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _fill,
        border: Border.all(color: _outline, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 8.h),
          ...head,
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Scrollbar(
                thumbVisibility: true,
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    Key? key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onAdd,
  }) : super(key: key);

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 12.h),
            ),
          ),
        ),
        SizedBox(width: 8.w),
        SizedBox(
          height: 40.h, // to match search height
          width: 40.h,
          child: OutlinedButton(
            onPressed: onAdd,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            child: const Icon(Icons.add, size: 18),
          ),
        ),
      ],
    );
  }
}

class _ListTileCard extends StatelessWidget {
  const _ListTileCard({Key? key, required this.label, required this.onTap}) : super(key: key);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(.9),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCenter extends StatelessWidget {
  const _EmptyCenter({Key? key, required this.text}) : super(key: key);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: TextStyle(fontSize: 14.sp, color: Colors.black54),
      ),
    );
  }
}
