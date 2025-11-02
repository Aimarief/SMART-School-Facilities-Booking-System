import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'web_top_bar.dart';


class CategoriesPage extends StatefulWidget {
  const CategoriesPage({Key? key}) : super(key: key);

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {

  final bool _use24HourFormat = true;
  final TextEditingController _searchCtrl = TextEditingController();

  String? _selectedCatId;
  String _selectedCatName = '';

  String _mode = 'view';

  final TextEditingController _newCtrl = TextEditingController();
  final TextEditingController _editCtrl = TextEditingController();
  final TextEditingController _viewCtrl = TextEditingController();
//---------------------------------------
//Clean the space for string
//---------------------------------------
  String _clean(String s) => s.trim();

  InputDecoration _commonInputDecoration() {
    return InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 15.h),
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

//---------------------------------------
// Use to check wether category name exist
//---------------------------------------
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
//---------------------------------------
// ingnore deleted
//---------------------------------------

        if (data['deleted'] == true) {
          deleted = true;
        } else {
          deleted = false;
        }

      String nm = '';
        nm = data['name'].toString().toLowerCase();
//---------------------------------------
// ignore same id name
//---------------------------------------

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
            i = snap.docs.length;
          }
        }
      }
      i = i + 1;
    }
    return exists;
  }

//---------------------------------------
// After adding a category
//---------------------------------------
  Future<void> _addCategory() async {
    final String name = _clean(_newCtrl.text);
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a category name')),
      );
      return;
    }
//---------------------------------------
// check if category already exist
//---------------------------------------

    if (await _categoryNameExists(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Category "$name" already exists')),
      );
      return;
    }
//---------------------------------------
// if no then add to database
//---------------------------------------
    try {
      final docRef = await FirebaseFirestore.instance
          .collection('FacilitiesCategory')
          .add({
        'name': name,
        'deleted': false,
        'createdAt': FieldValue.serverTimestamp(),
        'available':true,
      });
//---------------------------------------
// set to view mode and viewing the category id
//---------------------------------------
      setState(() {
        _selectedCatId = docRef.id;
        _selectedCatName = name;
        _viewCtrl.text = name;
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

//---------------------------------------
// when confirm button press, this will submit the things to firebase
//---------------------------------------
  Future<void> _saveEdit() async {
    if (_selectedCatId == null) {
      return;
    }
//---------------------------------------
// cannot empty
//---------------------------------------

    final String newName = _clean(_editCtrl.text);
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }
//---------------------------------------
// check if it is already exist
//---------------------------------------

    if (await _categoryNameExists(newName, ignoreId: _selectedCatId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Category "$newName" already exists')),
      );
      return;
    }
//---------------------------------------
// update the name in firebase
//---------------------------------------
    try {
      await FirebaseFirestore.instance
          .collection('FacilitiesCategory')
          .doc(_selectedCatId)
          .update({'name': newName});

//---------------------------------------
// set to view mode
//---------------------------------------
      setState(() {
        _selectedCatName = newName;
        _viewCtrl.text = newName;
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


//---------------------------------------
// show the confrim button pop up
//---------------------------------------
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
//---------------------------------------
// cancel button
//---------------------------------------

        actions: [
          TextButton(
            onPressed: () { Navigator.of(context).pop(false); },
            child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
          ),
//---------------------------------------
// confirm button
//---------------------------------------
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

//---------------------------------------
// perform soft delete
//---------------------------------------
  Future<void> _softDelete() async {
    if (_selectedCatId == null) {
      return;
    }
//---------------------------------------
// get the slected id
//---------------------------------------
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
//---------------------------------------
// set deleted to true
//---------------------------------------

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

//---------------------------------------
// Main build
//---------------------------------------
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
              constraints: BoxConstraints(minHeight: constraints.maxHeight), // let the box stretch even there is nothing, but will shrink when become small
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 1684.w,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
//---------------------------------------
// left box
//---------------------------------------
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
//---------------------------------------
// rigth box
//---------------------------------------

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

//---------------------------------------
// main build 2 The left side of the list
//---------------------------------------
  Widget _buildLeftList() {
    //---------------------------------------
// get the dream for category
//---------------------------------------

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
//---------------------------------------
//  get the search string anc compare with the category name
//---------------------------------------
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered =
        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final String q = _clean(_searchCtrl.text).toLowerCase();

        int i = 0;
        while (i < docs.length) {
          final d = docs[i];
          final data = d.data();
//---------------------------------------
// ingnore deleted category
//--------------------------------------
          bool del = false;
          if (data.containsKey('deleted')) {
            if (data['deleted'] == true) {
              del = true;
            } else {
              del = false;
            }
          }

          String nm = '';
          if (data.containsKey('name')) {
            nm = data['name'];
          } else {
            nm = '';
          }
//---------------------------------------
// check if the key word match
//---------------------------------------
          bool matches;
          if (q.isEmpty) {
            matches = true;
          } else {
            final String cname = nm.toLowerCase();
            if (cname.contains(q)) {
              matches = true;
            } else {
              matches = false;
            }
          }
//---------------------------------------
// if match adn not deleted add into filterd list
//---------------------------------------
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
//---------------------------------------
// list the category
//---------------------------------------
        final List<Widget> children = [];
        for (int i = 0; i < filtered.length; i++) {
          final d = filtered[i];
          final m = d.data();
          final String nm = (m['name']);

          children.add(
            _ListTileCard(
              label: nm,
              onTap: () {
                setState(() {
                  _selectedCatId = d.id;
                  _selectedCatName = nm;
                  _viewCtrl.text = nm;
                  _mode = 'view';
                });
              },
            ),
          );

          if (i < filtered.length - 1) {
            children.add(SizedBox(height: 8.h)); // separator after each item except last
          }
        }
//---------------------------------------
// return the the list
//---------------------------------------

        return ListView(
          children: children,
        );
      },
    );
  }

//---------------------------------------
// main build for the right side of the list make decision which mode is it in
//---------------------------------------

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

//---------------------------------------
// main design Add category form
//---------------------------------------
  Widget _panelAdd() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 6.h),
        Text('Add Category', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        SizedBox(height: 10.h),

        Text('Name', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
        SizedBox(height: 6.h),
//---------------------------------------
// text box
//---------------------------------------
        TextFormField(
          controller: _newCtrl,
          style: TextStyle(fontSize: 15.sp),
          decoration: _commonInputDecoration(),
        ),
        SizedBox(height: 14.h),
//---------------------------------------
// confirm add button
//---------------------------------------
        Row(
          children: [
            ElevatedButton(
              onPressed: _addCategory,
              child: const Text('Confirm'),
            ),
            SizedBox(width: 10.w),
            OutlinedButton(
              onPressed: () {
 //---------------------------------------
// cancel button
//---------------------------------------
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

//---------------------------------------
// main design for View mdoe
//---------------------------------------

  Widget _panelView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 6.h),
        Text('Details', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        SizedBox(height: 10.h),

        Text('Name', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)), // small label
        SizedBox(height: 6.h),
        TextFormField(
          //---------------------------------------
// display name but read only
//---------------------------------------
        key: ValueKey<String>('view|name|$_selectedCatName'),// view|name is just key to identify them without them after new name is place, it cant switch to other category
          initialValue: _selectedCatName,             // put the text once (no controller)
          enabled: false,                             // disabled = greyed out, not editable
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),

        SizedBox(height: 12.h),

//---------------------------------------
// edit and cancel button
//---------------------------------------
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
 //---------------------------------------
// close button
//---------------------------------------

            TextButton(
              onPressed: () {
                setState(() {
                  _selectedCatId = null;
                  _selectedCatName = '';
                  _mode = 'view';
                });
              },
              child: const Text('Close'),
            ),
 //---------------------------------------
// edit button
//---------------------------------------
            SizedBox(width: 8.w),
            ElevatedButton(
              onPressed: () {

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


//---------------------------------------
// main design for Edit form
//---------------------------------------
  Widget _panelEdit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 6.h),
        Text('Edit Category', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        SizedBox(height: 10.h),

        Text('Name', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
        SizedBox(height: 6.h),
        //---------------------------------------
//  text field for edit the category
//---------------------------------------
        TextFormField(
          controller: _editCtrl,
          style: TextStyle(fontSize: 17.sp),
          decoration: _commonInputDecoration(),
        ),
        SizedBox(height: 14.h),

//---------------------------------------
// delete button
//---------------------------------------
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
//---------------------------------------
// cancel button
//---------------------------------------

            SizedBox(width: 8.w),
            TextButton(
              onPressed: () {
                setState(() {
                  _mode = 'view';
                });
              },
              child: const Text('Cancel'),
            ),
//---------------------------------------
// confirm button
//---------------------------------------

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
    _viewCtrl.dispose();
    super.dispose();
  }
}

//---------------------------------------
// main design 1 class to design left and right box
//---------------------------------------

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
    //---------------------------------------
// if there is header , build header
//---------------------------------------
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
      //---------------------------------------
// display title
//---------------------------------------
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

//---------------------------------------
// search header
//---------------------------------------

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
          //---------------------------------------
// text field to taip, and set state when change
//---------------------------------------
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
//---------------------------------------
// add new category button
//---------------------------------------
        SizedBox(
          height: 40.h,
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
//---------------------------------------
// design for each category chip
//---------------------------------------
class _ListTileCard extends StatelessWidget {
  const _ListTileCard({Key? key,
    required this.label,
    required this.onTap
  }) : super(key: key);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(.9),
      borderRadius: BorderRadius.circular(8),
      //---------------------------------------
// each of the button for category chip
//---------------------------------------
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
          child: Row(
            children: [
              Expanded(
//---------------------------------------
// category name
//---------------------------------------
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
