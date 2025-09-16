import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore
import 'package:firebase_core/firebase_core.dart';      // secondary app
import 'package:firebase_auth/firebase_auth.dart';      // create auth user
import 'package:smart_school_facilities_booking_system/firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'web_top_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // FilteringTextInputFormatter

class WebListManager extends StatefulWidget {
  const WebListManager({Key? key}) : super(key: key);

  @override
  State<WebListManager> createState() => _WebListManagerState();
}

class _WebListManagerState extends State<WebListManager> {
  // ---------- UI state ----------
  final TextEditingController _search = TextEditingController();

  // Selected manager (no model, just doc id + Map like Facilities/Categories)
  String? _selectedId;
  Map<String, dynamic>? _selectedData;

  // Option A mode flag
  String _mode = 'view'; // 'view' | 'add' | 'edit'

  // ---------- Secondary auth for creating managers ----------
  FirebaseApp? _secApp;
  FirebaseAuth? _auth2;

  // ---------- Create flow ----------
  bool _creating = false;
  bool _hidePwd = true;

  // Add form controllers
  final TextEditingController _nameC = TextEditingController();
  final TextEditingController _emailC = TextEditingController();
  final TextEditingController _contactC = TextEditingController();
  final TextEditingController _pwdC = TextEditingController();
  final TextEditingController _roleDetailsC = TextEditingController();

  // Edit form controllers
  final TextEditingController _editNameC = TextEditingController();
  final TextEditingController _editContactC = TextEditingController();
  final TextEditingController _editRoleDetailsC = TextEditingController();

  // Form keys
  final GlobalKey<FormState> _addFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _editFormKey = GlobalKey<FormState>();

  // Email pattern
  final RegExp _emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');

  // ---------- Helpers ----------
  String _clean(String s) => s.trim();

  bool _isPasswordStrong(String s) {
    final RegExp regex = RegExp(r'^(?=.*[A-Z])(?=.*[!@#\$%^&*(),.?":{}|<>]).{8,}$');
    return regex.hasMatch(s);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applySearchDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final String q = _clean(_search.text).toLowerCase();
    if (q.isEmpty) return docs;

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in docs) {
      final Map<String, dynamic> m = d.data();
      String name = '';
      if (m['username'] != null) {
        name = m['username'].toString();
      } else if (m['name'] != null) {
        name = m['name'].toString();
      }
      if (name.toLowerCase().contains(q)) out.add(d);
    }
    return out;
  }

  void _onAddTap() {
    setState(() {
      _mode = 'add';
      _selectedId = null;
      _selectedData = null;
      _nameC.clear();
      _emailC.clear();
      _contactC.clear();
      _pwdC.clear();
      _roleDetailsC.clear();
    });
  }

  // ---------- Secondary Auth ----------
  Future<FirebaseAuth> _ensureSecondaryAuth() async {
    if (_secApp != null && _auth2 != null) return _auth2!;
    try {
      _secApp = Firebase.app('secondary');
    } catch (_) {
      _secApp = await Firebase.initializeApp(
        name: 'secondary',
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    _auth2 = FirebaseAuth.instanceFor(app: _secApp!);
    if (kIsWeb) {
      await _auth2!.setPersistence(Persistence.NONE);
    }
    return _auth2!;
  }

  // ---------- Create manager ----------
  Future<void> _createManager() async {
    if (_creating) return;
    _creating = true;

    final FormState? form = _addFormKey.currentState;
    if (form == null) {
      _creating = false;
      return;
    }
    if (!form.validate()) {
      _creating = false;
      return;
    }

    final String name = _nameC.text.trim();
    final String email = _emailC.text.trim();
    final String contact = _contactC.text.trim();
    final String pwd = _pwdC.text.trim();
    final String roleDetails = _roleDetailsC.text.trim();

    try {
      final List<String> methods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
      if (methods.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That email already has an account.')),
        );
        _creating = false;
        return;
      }

      final FirebaseAuth auth2 = await _ensureSecondaryAuth();
      final UserCredential cred = await auth2.createUserWithEmailAndPassword(email: email, password: pwd);

      if (cred.user != null) {
        await cred.user!.updateDisplayName(name);
      }

      final String uid = cred.user?.uid ?? '';

      await FirebaseFirestore.instance.collection('UserInformation').doc(uid).set({
        'username': name,
        'email': email,
        'contact': contact,
        'role': 'Manager',
        'roleDetails': roleDetails,
        'isVerified': false,
        'notifAll': true,
        'notifIssue': true,
        'notifNewBooking': true,
        'notifPending': true,
        'timeFormat24': true,
        'profileImageName': null,
        'deleted': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      bool emailSent = false;
      try {
        await cred.user?.sendEmailVerification();
        emailSent = true;
      } catch (_) {
        emailSent = false;
      }

      if (!mounted) {
        _creating = false;
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(emailSent
            ? 'Manager created. Verification email sent.'
            : 'Manager created. Couldn’t send verification email right now.')),
      );

      setState(() => _mode = 'view');
    } on FirebaseAuthException catch (e) {
      String msg = 'Authentication error';
      if (e.code == 'email-already-in-use') {
        msg = 'That email already has an account.';
      } else if (e.message != null) {
        msg = e.message!;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      try {
        await _auth2?.signOut();
      } catch (_) {}
      _creating = false;
    }
  }

  // ---------- Save edits ----------
  Future<void> _saveEdits() async {
    if (_selectedId == null) return;

    final FormState? form = _editFormKey.currentState;
    if (form == null || !form.validate()) return;

    final String newName = _editNameC.text.trim();
    final String newContact = _editContactC.text.trim();
    final String newRoleDetails = _editRoleDetailsC.text.trim();

    try {
      await FirebaseFirestore.instance
          .collection('UserInformation')
          .doc(_selectedId!)
          .update({
        'username': newName,
        'contact': newContact,
        'roleDetails': newRoleDetails,
      });

      _selectedData ??= <String, dynamic>{};
      _selectedData!['username'] = newName;
      _selectedData!['contact'] = newContact;
      _selectedData!['roleDetails'] = newRoleDetails;

      setState(() => _mode = 'view');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  // ---------- Delete (soft delete) ----------
  Future<void> _deleteManager() async {
    if (_selectedId == null || _selectedData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a manager first')),
      );
      return;
    }

    try {
      // UPDATED: block delete if any facility references this managerId
      final QuerySnapshot<Map<String, dynamic>> f = await FirebaseFirestore.instance
          .collection('Facilities')
          .where('managerId', isEqualTo: _selectedId)
          .limit(1)
          .get();

      if (f.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Make sure the manager has no facility to manage')),
        );
        return;
      }

      await FirebaseFirestore.instance
          .collection('UserInformation')
          .doc(_selectedId!)
          .update({'deleted': true});

      if (!mounted) return;



      setState(() {
        _selectedId = null;
        _selectedData = null;
        _mode = 'view';
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  // ---------- Lifecycle ----------
  @override
  void dispose() {
    _search.dispose();
    _nameC.dispose();
    _emailC.dispose();
    _contactC.dispose();
    _pwdC.dispose();
    _roleDetailsC.dispose();
    _editNameC.dispose();
    _editContactC.dispose();
    _editRoleDetailsC.dispose();
    super.dispose();
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: const WebCustomTopBar(use24HourFormat: true),
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
                      constraints: BoxConstraints(maxWidth: 460.w + 24.w + 1200.w),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // LEFT
                          _Box(
                            width: 460.w,
                            height: 965.h,
                            title: 'Manager',
                            header: _SearchHeader(
                              controller: _search,
                              hint: 'Search',
                              onChanged: (_) => setState(() {}),
                              onAdd: _onAddTap,
                            ),
                            child: _buildLeftList(),
                          ),
                          SizedBox(width: 24.w),
                          // RIGHT
                          _Box(
                            width: 1200.w,
                            height: 965.h,
                            title: 'Details',
                            child: SingleChildScrollView(
                              padding: EdgeInsets.only(right: 8.w, bottom: 8.h),
                              child: _buildRightPanel(),
                            ),
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

  String _docName(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final Map<String, dynamic> m = d.data();
    String nm = '';
    if (m['username'] != null) {
      nm = m['username'].toString();
    } else if (m['name'] != null) {
      nm = m['name'].toString();
    }
    return nm;
  }

  Widget _buildLeftList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('UserInformation')
          .where('role', isEqualTo: 'Manager')
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('Managers stream error: ${snap.error}');
          return Center(child: Text('Failed to load', style: TextStyle(fontSize: 14.sp)));
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: Text('Loading...', style: TextStyle(fontSize: 14.sp)));
        }

        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        // filter out soft-deleted
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> active = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final d in docs) {
          final m = d.data();
          final bool deleted = (m['deleted'] == true);
          if (!deleted) active.add(d);
        }

        // search + sort
        final filtered = _applySearchDocs(active);
        final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(filtered)
          ..sort((a, b) => _docName(a).toLowerCase().compareTo(_docName(b).toLowerCase()));

        if (sorted.isEmpty) {
          return const _EmptyCenter(text: 'empty');
        }

        return ListView.separated(
          itemCount: sorted.length,
          separatorBuilder: (_, __) => SizedBox(height: 8.h),
          itemBuilder: (context, i) {
            final doc = sorted[i];
            final Map<String, dynamic> m = doc.data();

            String nm = '';
            if (m['username'] != null) {
              nm = m['username'].toString();
            } else if (m['name'] != null) {
              nm = m['name'].toString();
            }

            return _ListTileCard(
              label: nm,
              onTap: () {
                setState(() {
                  _selectedId = doc.id;
                  _selectedData = m;

                  _editNameC.text = nm;
                  _editContactC.text = (m['contact'] ?? '').toString();
                  _editRoleDetailsC.text = (m['roleDetails'] ?? m['managerRole'] ?? '').toString();

                  _mode = 'view';
                });
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRightPanel() {
    if (_mode == 'add') return _buildAddForm();

    if (_selectedId == null || _selectedData == null) {
      return SizedBox(
        height: 820.h,
        child: Center(
          child: Text(
            'Please select an option',
            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return KeyedSubtree(
      key: ValueKey<String>(_selectedId!),
      child: _buildSelectedDetails(_selectedData!),
    );
  }

  // ---------- Small UI helpers ----------
  Widget _roField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
        SizedBox(height: 6.h),
        TextFormField(
          initialValue: value,
          enabled: false,
          decoration: InputDecoration(
            isDense: true,
            disabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFCBC3FF)),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
          ),
        ),
        SizedBox(height: 14.h),
      ],
    );
  }



  Widget _editField(
      String label,
      TextEditingController c, {
        TextInputType type = TextInputType.text,
        List<TextInputFormatter>? inputFormatters,
        String? Function(String?)? validator,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
        SizedBox(height: 6.h),
        TextFormField(
          controller: c,
          keyboardType: type,
          inputFormatters: inputFormatters,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: validator,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFCBC3FF)),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
            fillColor: Colors.white,
            filled: true,
          ),
        ),
        SizedBox(height: 14.h),
      ],
    );
  }

  // ---------- Selected details (view/edit) ----------
  Widget _buildSelectedDetails(Map<String, dynamic> m) {
    final List<Widget> children = <Widget>[SizedBox(height: 12.h)];

    String name = '';
    if (m['username'] != null) {
      name = m['username'].toString();
    } else if (m['name'] != null) {
      name = m['name'].toString();
    }

    final String email = (m['email'] ?? '').toString();
    final String contact = (m['contact'] ?? '').toString();
    final String role = (m['role'] ?? '').toString();
    final String roleDetails = (m['roleDetails'] ?? m['managerRole'] ?? '').toString();
    final bool isVerified = (m['isVerified'] == true);

    if (_mode == 'edit') {
      children.add(_editField(
        'Manager Name',
        _editNameC,
        validator: (v) {
          if (v == null) return 'Name cannot be empty';
          final String t = v.trim();
          if (t.isEmpty) return 'Name cannot be empty';
          return null;
        },
      ));
    } else {
      children.add(_roField('Manager Name', name));
    }

    children.add(_roField('Manager Email', email));

    if (_mode == 'edit') {
      children.add(_editField(
        'Manager Contact',
        _editContactC,
        type: TextInputType.phone,
        inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
        validator: (v) {
          if (v == null) return 'Contact cannot be empty';
          final String t = v.trim();
          if (t.isEmpty) return 'Contact cannot be empty';
          if (!RegExp(r'^\d+$').hasMatch(t)) return 'Digits only';
          return null;
        },
      ));
    } else {
      children.add(_roField('Manager Contact', contact));
    }

    children.add(_roField('Manager Role', role));

    if (_mode == 'edit') {
      children.add(_editField('Role Details', _editRoleDetailsC));
    } else {
      children.add(_roField('Role Details', roleDetails.isEmpty ? '-' : roleDetails));
    }

    children.add(_roField('Status', isVerified ? 'Active' : 'Inactive'));

    // Facilities under this manager (UPDATED: match by managerId == _selectedId)
    children.add(Text('Manage Facility',
        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)));
    children.add(SizedBox(height: 8.h));

    children.add(
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('Facilities')
            .where('managerId', isEqualTo: _selectedId)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            );
          }

          final docs = snap.data!.docs;

          // filter out soft-deleted facilities if present
          final active = docs.where((d) => (d.data()['deleted'] != true)).toList();

          if (active.isEmpty) {
            return Padding(
              padding: EdgeInsets.only(top: 6.h),
              child: Text(
                'No facility to manage',
                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500),
              ),
            );
          }

          final List<Widget> tiles = <Widget>[];
          for (final d in active) {
            final m = d.data();
            final String facName = (m['facilityName'] ?? m['name'] ?? 'Unnamed').toString();

            tiles.add(
              Container(
                width: 380.w,
                margin: EdgeInsets.only(bottom: 10.h),
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFCBC3FF)),
                ),
                alignment: Alignment.centerLeft,
                child: Text(
                  facName,
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }

          return Column(children: tiles);
        },
      ),
    );

    children.add(SizedBox(height: 20.h));

    final List<Widget> actions = <Widget>[];
    if (_mode == 'edit') {
      actions.add(
        TextButton(
          onPressed: () async {
            final bool ok = await _confirmDeleteManager();
            if (ok) await _deleteManager();
          },


          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Delete'),
        ),
      );
      actions.add(SizedBox(width: 8.w));
      actions.add(
        TextButton(
          onPressed: () => setState(() => _mode = 'view'),
          child: const Text('Cancel'),
        ),
      );
      actions.add(SizedBox(width: 8.w));
      actions.add(
        ElevatedButton(
          onPressed: _saveEdits,
          child: const Text('Confirm'),
        ),
      );
    } else {
      actions.add(
        ElevatedButton(
          onPressed: () {
            _editNameC.text = name;
            _editContactC.text = contact;
            _editRoleDetailsC.text = roleDetails;
            setState(() => _mode = 'edit');
          },
          child: const Text('Edit'),
        ),
      );
    }

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );

    if (_mode == 'edit') {
      return Padding(
        padding: EdgeInsets.all(12.w),
        child: Form(
          key: _editFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              content,
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ],
          ),
        ),
      );
    } else {
      return Padding(
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            content,
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ],
        ),
      );
    }
  }

  Future<bool> _confirmDeleteManager() async {
    final bool? res = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // block tap-outside to close
      builder: (_) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          'Delete manager?',
          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to delete this manager?',
          style: TextStyle(fontSize: 14.sp),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
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
    return res ?? false;
  }


  // ---------- Add form ----------
  Widget _vField(
      String label,
      TextEditingController c, {
        TextInputType type = TextInputType.text,
        List<TextInputFormatter>? inputFormatters,
        String? Function(String?)? validator,
        bool obscure = false,
        Widget? suffixIcon,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
        SizedBox(height: 6.h),
        TextFormField(
          controller: c,
          keyboardType: type,
          obscureText: obscure,
          inputFormatters: inputFormatters,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: validator,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Color(0xFFCBC3FF)),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
            fillColor: Colors.white,
            filled: true,
            suffixIcon: suffixIcon,
          ),
        ),
        SizedBox(height: 14.h),
      ],
    );
  }

  Widget _buildAddForm() {
    return Padding(
      padding: EdgeInsets.all(12.w),
      child: Form(
        key: _addFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add Manager', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 12.h),

            _vField(
              'Manager Name',
              _nameC,
              validator: (v) {
                if (v == null) return 'Name cannot be empty';
                final String t = v.trim();
                if (t.isEmpty) return 'Name cannot be empty';
                return null;
              },
            ),

            _vField(
              'Manager Email',
              _emailC,
              type: TextInputType.emailAddress,
              validator: (v) {
                if (v == null) return 'Email cannot be empty';
                final String t = v.trim();
                if (t.isEmpty) return 'Email cannot be empty';
                if (!_emailRegex.hasMatch(t)) return 'Enter a valid email';
                return null;
              },
            ),

            _vField(
              'Manager Contact',
              _contactC,
              type: TextInputType.phone,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (v == null) return 'Contact cannot be empty';
                final String t = v.trim();
                if (t.isEmpty) return 'Contact cannot be empty';
                if (!RegExp(r'^\d+$').hasMatch(t)) return 'Digits only';
                return null;
              },
            ),

            _vField(
              'Password',
              _pwdC,
              obscure: _hidePwd,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _hidePwd = !_hidePwd),
                icon: Icon(_hidePwd ? Icons.visibility : Icons.visibility_off),
              ),
              validator: (v) {
                if (v == null) return 'Password cannot be empty';
                if (v.isEmpty) return 'Password cannot be empty';
                if (!_isPasswordStrong(v)) {
                  return 'Password must be at least 8 characters, include 1 uppercase letter and 1 special character';
                }
                return null;
              },
            ),

            Text('Role', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
            SizedBox(height: 6.h),
            const TextField(
              enabled: false,
              decoration: InputDecoration(
                isDense: true,
                disabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFCBC3FF)),
                ),
                filled: true,
                hintText: 'Manager',
              ),
            ),
            SizedBox(height: 14.h),

            _vField('Role Details', _roleDetailsC),

            Row(
              children: [
                ElevatedButton(onPressed: _createManager, child: const Text('Create')),
                SizedBox(width: 12.w),
                OutlinedButton(
                  onPressed: () => setState(() => _mode = 'view'),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Reusable UI parts ----------

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
      decoration: BoxDecoration(
        color: _fill,
        border: Border.all(color: _outline, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: kids,
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
              contentPadding: EdgeInsets.symmetric(vertical: 10.h),
            ),
          ),
        ),
        SizedBox(width: 8.w),
        SizedBox(
          height: 36.h,
          width: 36.h,
          child: OutlinedButton(
            onPressed: onAdd,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            child: const Icon(Icons.person_add_alt_1, size: 18),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
