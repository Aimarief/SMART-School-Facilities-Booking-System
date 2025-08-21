import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

enum CatView { add, view, edit }

/// -------- Small reusable box with sticky header (visual wrapper) --------
class _BoxPanel extends StatelessWidget {
  const _BoxPanel({
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

  static const Color _fill = Color(0xFFEDDFFF);
  static const Color _outline = Color(0xFF8620E2);

  @override
  Widget build(BuildContext context) {
    final List<Widget> kids = <Widget>[
      Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
      SizedBox(height: 8.h),
    ];
    if (header != null) {
      kids.add(header!);
      kids.add(SizedBox(height: 8.h));
    }
    kids.add(
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Scrollbar(
            thumbVisibility: true,
            child: child,
          ),
        ),
      ),
    );

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outline, width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids),
    );
  }
}

/// -------- Search header with + button (top of left list) --------
class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    Key? key,
    required this.controller,
    required this.onChanged,
    required this.onAddTap,
  }) : super(key: key);

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 36.h,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
        ),
        SizedBox(width: 8.w),
        SizedBox(
          height: 36.h,
          width: 36.h,
          child: OutlinedButton(
            onPressed: onAddTap,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            child: const Icon(Icons.playlist_add, size: 18),
          ),
        ),
      ],
    );
  }
}

/// -------- List row (left list item) --------
class _ListTileCard extends StatelessWidget {
  const _ListTileCard({
    Key? key,
    required this.label,
    required this.onTap,
  }) : super(key: key);

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
          height: 44.h,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
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

/// =======================================================
/// LEFT: Categories list + search + add
/// =======================================================
class CategoryLeftList extends StatefulWidget {
  const CategoryLeftList({
    Key? key,
    required this.width,
    required this.height,
    required this.search,
    required this.onAddTap,
    required this.onSelect,
  }) : super(key: key);

  final double width;
  final double height;
  final TextEditingController search;

  /// Called when “+” button is pressed (parent switches right panel to add mode)
  final VoidCallback onAddTap;

  /// Called when a category is tapped → parent shows details on the right
  final void Function(String id, String name, bool available) onSelect;

  @override
  State<CategoryLeftList> createState() => _CategoryLeftListState();
}

class _CategoryLeftListState extends State<CategoryLeftList> {
  Stream<QuerySnapshot<Map<String, dynamic>>> _catsStream() {
    return FirebaseFirestore.instance
        .collection('FacilitiesCategory')
        .orderBy('name')
        .snapshots();
  }

  String _clean(String s) => s.trim();

  @override
  Widget build(BuildContext context) {
    return _BoxPanel(
      width: widget.width,
      height: widget.height,
      title: 'Categories',
      header: _SearchHeader(
        controller: widget.search,
        onChanged: (_) => setState(() {}),
        onAddTap: widget.onAddTap,
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _catsStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: Text('Loading...', style: TextStyle(fontSize: 14.sp)));
          }
          if (snap.hasError) {
            return Center(child: Text('Failed to load', style: TextStyle(fontSize: 14.sp)));
          }

          List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          if (snap.hasData) {
            docs = snap.data!.docs;
          }

          final String q = _clean(widget.search.text).toLowerCase();
          final List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

          for (final d in docs) {
            final Map<String, dynamic> m = d.data();
            final bool del = (m['deleted'] == true);

            String name = '';
            if (m.containsKey('name') && m['name'] != null) {
              name = m['name'].toString();
            }

            final bool matches = q.isEmpty ? true : name.toLowerCase().contains(q);

            if (!del && matches) {
              filtered.add(d);
            }
          }

          if (filtered.isEmpty) {
            return Center(child: Text('empty', style: TextStyle(fontSize: 14.sp)));
          }

          return ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, __) => SizedBox(height: 8.h),
            itemBuilder: (context, i) {
              final doc = filtered[i];
              final Map<String, dynamic> data = doc.data();

              final String name = (data['name'] ?? '').toString();
              final bool available = (data['available'] is bool) ? data['available'] as bool : true;

              return _ListTileCard(
                label: name,
                onTap: () => widget.onSelect(doc.id, name, available),
              );
            },
          );
        },
      ),
    );
  }
}

/// =======================================================
/// RIGHT: Category Details Panel (add / view / edit)
/// =======================================================
class CategoryRightPanel extends StatefulWidget {
  const CategoryRightPanel({
    Key? key,
    required this.width,
    required this.height,
    required this.selectedCatId,
    required this.selectedCatName,
    required this.selectedCatAvailable,
    required this.initialView,
    required this.onClose,
    required this.onCategoryUpdated,
  }) : super(key: key);

  final double width;
  final double height;

  final String? selectedCatId;
  final String selectedCatName;
  final bool selectedCatAvailable;

  final CatView initialView;

  final VoidCallback onClose;

  final void Function(String? id, String name, bool available) onCategoryUpdated;

  @override
  State<CategoryRightPanel> createState() => _CategoryRightPanelState();
}

class _CategoryRightPanelState extends State<CategoryRightPanel> {
  CatView _view = CatView.view;

  final TextEditingController _newCtrl = TextEditingController();
  final TextEditingController _editCtrl = TextEditingController();
  bool _availableSwitch = true;

  String _clean(String s) => s.trim();

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
    _availableSwitch = widget.selectedCatAvailable;
    if (_view == CatView.edit) {
      _editCtrl.text = widget.selectedCatName;
    }
  }

  @override
  void didUpdateWidget(covariant CategoryRightPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Follow parent if it explicitly changes the view.
    if (oldWidget.initialView != widget.initialView) {
      setState(() {
        _view = widget.initialView;
        if (_view == CatView.add) _newCtrl.clear();
        if (_view == CatView.edit) _editCtrl.text = widget.selectedCatName;
      });
    }

    // Keep local toggles/fields in sync with selection changes.
    if (oldWidget.selectedCatAvailable != widget.selectedCatAvailable) {
      _availableSwitch = widget.selectedCatAvailable;
    }
    if (oldWidget.selectedCatName != widget.selectedCatName && _view == CatView.edit) {
      _editCtrl.text = widget.selectedCatName;
    }
  }

  @override
  void dispose() {
    _newCtrl.dispose();
    _editCtrl.dispose();
    super.dispose();
  }

  // ---------------- Firestore helpers ----------------

  Future<bool> _categoryNameExists(String name, {String? ignoreId}) async {
    final qs = await FirebaseFirestore.instance
        .collection('FacilitiesCategory')
        .where('name', isEqualTo: _clean(name))
        .where('deleted', isEqualTo: false)
        .limit(2)
        .get();

    for (final d in qs.docs) {
      if (d.id != ignoreId) return true;
    }
    return false;
  }

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
        'available': true,
        'deleted': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _newCtrl.clear();

      // Tell the parent and show the newly added item in View mode.
      widget.onCategoryUpdated(docRef.id, name, true);
      setState(() => _view = CatView.view);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Category "$name" added')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add: $e')),
      );
    }
  }

  Future<void> _toggleAvailability(bool v) async {
    if (widget.selectedCatId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('FacilitiesCategory')
          .doc(widget.selectedCatId)
          .update({'available': v});

      setState(() {
        _availableSwitch = v;
      });

      widget.onCategoryUpdated(widget.selectedCatId, widget.selectedCatName, v);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _saveEdit() async {
    if (widget.selectedCatId == null) return;

    final String newName = _clean(_editCtrl.text);
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name cannot be empty')));
      return;
    }

    if (await _categoryNameExists(newName, ignoreId: widget.selectedCatId)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Category "$newName" already exists')));
      return;
    }

    await FirebaseFirestore.instance
        .collection('FacilitiesCategory')
        .doc(widget.selectedCatId)
        .update({'name': newName});

    await _propagateCategoryNameChange(widget.selectedCatId!, newName);

    widget.onCategoryUpdated(widget.selectedCatId, newName, _availableSwitch);
    setState(() => _view = CatView.view);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category updated')));
  }

  Future<int> _propagateCategoryNameChange(String catId, String newName) async {
    final db = FirebaseFirestore.instance;

    final snap = await db
        .collection('Facilities')
        .where('categoryId', isEqualTo: catId)
        .where('deleted', isEqualTo: false)
        .get();

    int i = 0;
    while (i < snap.docs.length) {
      final int end = (i + 400 < snap.docs.length) ? i + 400 : snap.docs.length;
      final batch = db.batch();
      for (int j = i; j < end; j++) {
        batch.update(snap.docs[j].reference, {'categoryName': newName});
      }
      await batch.commit();
      i = end;
    }
    return snap.docs.length;
  }

  Future<bool> _confirmDelete() async {
    final bool? res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm delete'),
        content: const Text('Are you sure you want to delete this category?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('No')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Future<void> _softDelete() async {
    if (widget.selectedCatId == null) return;

    final facSnap = await FirebaseFirestore.instance
        .collection('Facilities')
        .where('categoryId', isEqualTo: widget.selectedCatId)
        .get();

    for (final d in facSnap.docs) {
      final m = d.data();
      final bool isDeleted = (m['deleted'] == true);
      if (!isDeleted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This category still contains facilities. Please delete the facilities first.'),
        ));
        return;
      }
    }

    await FirebaseFirestore.instance
        .collection('FacilitiesCategory')
        .doc(widget.selectedCatId)
        .update({'deleted': true});

    widget.onCategoryUpdated(null, '', true);
    widget.onClose();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category deleted')));
  }

  // ---------------- UI helpers ----------------

  Widget _ro(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
        SizedBox(height: 6.h),
        TextFormField(
          key: ValueKey<String>('$label|$value'),
          initialValue: value,
          enabled: false,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
        ),
        SizedBox(height: 12.h),
      ],
    );
  }

  // ---------------- Build ----------------

  @override
  Widget build(BuildContext context) {
    return _BoxPanel(
      width: widget.width,
      height: widget.height,
      title: 'Details (Category)',
      child: SingleChildScrollView(
        padding: EdgeInsets.only(right: 8.w, bottom: 8.h),
        child: _buildInner(),
      ),
    );
  }

  Widget _buildInner() {
    if (_view == CatView.add) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Category Name', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          SizedBox(
            height: 40.h,
            child: TextField(
              controller: _newCtrl,
              style: TextStyle(fontSize: 14.sp),
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              ElevatedButton(onPressed: _addCategory, child: const Text('Add')),
              SizedBox(width: 8.w),
              TextButton(onPressed: widget.onClose, child: const Text('Cancel')),
            ],
          ),
        ],
      );
    }

    if (_view == CatView.view) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ro('Category', widget.selectedCatName),
          Row(
            children: [
              Text('Enabled', style: TextStyle(fontSize: 15.sp)),
              SizedBox(width: 8.w),
              Switch(value: _availableSwitch, onChanged: _toggleAvailability),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              ElevatedButton(
                onPressed: () {
                  _editCtrl.text = widget.selectedCatName;
                  setState(() => _view = CatView.edit);
                },
                child: const Text('Edit'),
              ),
              SizedBox(width: 8.w),
              TextButton(onPressed: widget.onClose, child: const Text('Close')),
            ],
          ),
        ],
      );
    }

    // EDIT
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Edit Category Name', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
        SizedBox(height: 6.h),
        SizedBox(
          height: 40.h,
          child: TextField(
            controller: _editCtrl,
            style: TextStyle(fontSize: 14.sp),
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          ),
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            ElevatedButton(onPressed: _saveEdit, child: const Text('Confirm')),
            SizedBox(width: 8.w),
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
              onPressed: () => setState(() => _view = CatView.view),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}

/// =======================================================================
/// All-in-one master/detail wrapper (use this if your parent isn’t wired yet)
/// =======================================================================
class CategoryMasterDetail extends StatefulWidget {
  const CategoryMasterDetail({
    super.key,
    required this.leftWidth,
    required this.rightWidth,
    required this.height,
  });

  final double leftWidth;
  final double rightWidth;
  final double height;

  @override
  State<CategoryMasterDetail> createState() => _CategoryMasterDetailState();
}

class _CategoryMasterDetailState extends State<CategoryMasterDetail> {
  final TextEditingController _search = TextEditingController();

  String? _selectedCatId;
  String _selectedCatName = '';
  bool _selectedCatAvailable = true;

  CatView _rightView = CatView.view;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // LEFT
        CategoryLeftList(
          width: widget.leftWidth,
          height: widget.height,
          search: _search,
          onAddTap: () {
            setState(() {
              // Clear selection, switch to Add
              _selectedCatId = null;
              _selectedCatName = '';
              _selectedCatAvailable = true;
              _rightView = CatView.add;
            });
          },
          onSelect: (id, name, available) {
            setState(() {
              _selectedCatId = id;
              _selectedCatName = name;
              _selectedCatAvailable = available;
              _rightView = CatView.view;
            });
          },
        ),

        SizedBox(width: 16.w),

        // RIGHT
        Expanded(
          child: CategoryRightPanel(
            key: ValueKey('right-${_selectedCatId ?? 'new'}-${_rightView.name}'),
            width: widget.rightWidth,
            height: widget.height,
            selectedCatId: _selectedCatId,
            selectedCatName: _selectedCatName,
            selectedCatAvailable: _selectedCatAvailable,
            initialView: _rightView,
            onClose: () => setState(() => _rightView = CatView.view),
            onCategoryUpdated: (id, name, available) {
              // After add/rename/toggle/delete
              setState(() {
                _selectedCatId = id;
                _selectedCatName = name;
                _selectedCatAvailable = available;
                _rightView = CatView.view;
              });
            },
          ),
        ),
      ],
    );
  }
}
