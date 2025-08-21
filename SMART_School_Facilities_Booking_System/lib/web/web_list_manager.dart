import 'package:cloud_firestore/cloud_firestore.dart'; // <-- Firestore database
import 'package:firebase_core/firebase_core.dart';      // init extra app
import 'package:firebase_auth/firebase_auth.dart';      // auth create user
import 'package:smart_school_facilities_booking_system/firebase_options.dart';
import 'package:flutter/material.dart';               // <-- Flutter UI toolkit
import 'package:flutter_screenutil/flutter_screenutil.dart'; // <-- responsive .w/.h/.sp
import 'web_top_bar.dart';                            // <-- your reusable top bar
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // for FilteringTextInputFormatter'

/* ============================================================================
  SECTION 1: DATA MODEL (simple class to hold one Manager row)
  - NOTE: In Dart, a class definition must be at TOP-LEVEL (not inside State).
  - We keep it very simple and readable (no "??", no ternary "? :").
============================================================================ */

class ManagerItem {
  // "final" = set once in constructor and cannot be changed later.
  // This prevents accidental changes (safer for UI state).
  final String id;           // Firestore document id
  final String name;         // manager name (username/display)
  final String email;        // manager email
  final String contact;      // manager contact/phone
  final String role;         // should be "Manager"
  final String? statusTag;   // "Pending" when not verified, otherwise null
  final String? roleDetails; // optional extra info
  final bool isVerified;     // true = Active, false = Inactive

  // Constructor: "required" means the caller must provide a value
  ManagerItem({
    required this.id,
    required this.name,
    required this.email,
    required this.contact,
    required this.role,
    required this.isVerified,
    this.statusTag,
    this.roleDetails,
  });

  // Helper to build ManagerItem from a Firestore DocumentSnapshot
  // We avoid "??" and use normal if/else to make it easy to read.
  factory ManagerItem.fromDoc(DocumentSnapshot doc) {
    // Get the raw data safely as a Map<String, dynamic>
    Map<String, dynamic> d = {};
    final raw = doc.data();
    if (raw is Map<String, dynamic>) {
      d = raw;
    }

    // Read "isVerified" safely
    bool isVerified = false;
    if (d.containsKey('isVerified')) {
      if (d['isVerified'] == true) {
        isVerified = true;
      }
    }

    // Read strings safely with default "" when missing
    String name = '';
    if (d.containsKey('username') && d['username'] != null) {
      name = d['username'].toString();
    }

    String email = '';
    if (d.containsKey('email') && d['email'] != null) {
      email = d['email'].toString();
    }

    String contact = '';
    if (d.containsKey('contact') && d['contact'] != null) {
      contact = d['contact'].toString();
    }

    String role = '';
    if (d.containsKey('role') && d['role'] != null) {
      role = d['role'].toString();
    }

    // Read roleDetails with a fallback to old key "managerRole"
    String roleDetailsStr = '';
    if (d.containsKey('roleDetails') && d['roleDetails'] != null) {
      roleDetailsStr = d['roleDetails'].toString();
    } else {
      if (d.containsKey('managerRole') && d['managerRole'] != null) {
        roleDetailsStr = d['managerRole'].toString();
      }
    }
    String? finalRoleDetails = roleDetailsStr.isEmpty ? null : roleDetailsStr;

    // Build statusTag using if/else (no ternary)
    String? statusTag;
    if (isVerified) {
      statusTag = null;
    } else {
      statusTag = 'Pending';
    }

    // Return the model object
    return ManagerItem(
      id: doc.id,
      name: name,
      email: email,
      contact: contact,
      role: role,
      isVerified: isVerified,
      statusTag: statusTag,
      roleDetails: finalRoleDetails,
    );
  }
}

/* ============================================================================
  SECTION 2: LIVE STREAM (read managers from Firestore, filter deleted)
  - Returns Stream<List<ManagerItem>>
  - Uses plain loops and if/else (no "where", no nested map chains)
============================================================================ */

Stream<List<ManagerItem>> get _managerStream {
  // Start a realtime stream of snapshots
  return FirebaseFirestore.instance
      .collection('UserInformation')
      .where('role', isEqualTo: 'Manager')
      .snapshots()
      .map((snap) {
    // Convert QuerySnapshot -> List<ManagerItem> with a simple loop
    final List<ManagerItem> list = [];
    for (final doc in snap.docs) {
      // Skip if "deleted" is true
      bool deleted = false;
      final dataRaw = doc.data();
      if (dataRaw is Map<String, dynamic>) {
        if (dataRaw.containsKey('deleted') && dataRaw['deleted'] == true) {
          deleted = true;
        }
      }
      if (deleted) {
        continue;
      }

      // Add to list
      final item = ManagerItem.fromDoc(doc);
      list.add(item);
    }
    return list;
  });
}

/* ============================================================================
  SECTION 3: STATEFUL PAGE (controllers, flags, helpers)
  - Holds UI state (selected row, search box, edit/add flags)
============================================================================ */

class WebListManager extends StatefulWidget {
  const WebListManager({Key? key}) : super(key: key);

  @override
  State<WebListManager> createState() => _WebListManagerState();
}

class _WebListManagerState extends State<WebListManager> {
  // Text controller for the search box
  final TextEditingController _search = TextEditingController();

  // Selected manager in the right panel (null = nothing selected)
  ManagerItem? _selected;

  // UI flags
  bool _isAdding = false;   // true = show add form
  bool _isEditing = false;  // true = edit mode on right panel

  // Secondary Firebase app/auth (used to create manager without logging out admin)
  FirebaseApp? _secApp;
  FirebaseAuth? _auth2;

  // Create flow flags
  bool _creating = false; // true = currently creating a manager
  bool _hidePwd = true;   // true = password hidden in the add form

  // Add-form controllers
  final TextEditingController _nameC = TextEditingController();
  final TextEditingController _emailC = TextEditingController();
  final TextEditingController _contactC = TextEditingController();
  final TextEditingController _pwdC = TextEditingController();
  final TextEditingController _roleDetailsC = TextEditingController();

  // Edit-form controllers
  final TextEditingController _editNameC = TextEditingController();
  final TextEditingController _editContactC = TextEditingController();
  final TextEditingController _editRoleDetailsC = TextEditingController();

  // Form keys for validation
  final GlobalKey<FormState> _addFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _editFormKey = GlobalKey<FormState>();

  // Email pattern (simple)
  final RegExp _emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');

  // Simple password rule: 8+ chars, 1 uppercase, 1 special char
  bool _isPasswordStrong(String s) {
    final RegExp regex = RegExp(r'^(?=.*[A-Z])(?=.*[!@#\$%^&*(),.?":{}|<>]).{8,}$');
    return regex.hasMatch(s);
  }

  // Filter the manager list by text in _search (very simple contains)
  List<ManagerItem> _applySearch(List<ManagerItem> list) {
    final String q = _search.text.trim().toLowerCase();
    if (q.isEmpty) {
      return list;
    }

    final List<ManagerItem> filtered = [];
    for (final m in list) {
      final String nameLower = m.name.toLowerCase();
      if (nameLower.contains(q)) {
        filtered.add(m);
      }
    }
    return filtered;
  }

  // Handle click on the "add" (+) button
  void _onAddManager() {
    setState(() {
      _isAdding = true;   // show add form
      _selected = null;   // nothing selected on right panel
      _nameC.text = '';
      _emailC.text = '';
      _contactC.text = '';
      _pwdC.text = '';
      _roleDetailsC.text = '';
    });
  }

  /* ==========================================================================
    SECTION 4A: CREATE MANAGER (secondary Firebase app, no admin logout)
    - Validates form
    - Creates auth user on secondary app
    - Writes Firestore doc
    - Sends verification email (best-effort)
  ========================================================================= */

  Future<void> _createManager() async {
    // Do nothing if already creating (avoid double taps)
    if (_creating) {
      return;
    }
    _creating = true;

    // Validate the form: show errors if invalid
    final FormState? form = _addFormKey.currentState;
    if (form == null) {
      _creating = false;
      return;
    }
    final bool isValid = form.validate();
    if (!isValid) {
      _creating = false;
      return;
    }

    // Read values
    final String name = _nameC.text.trim();
    final String email = _emailC.text.trim();
    final String contact = _contactC.text.trim();
    final String pwd = _pwdC.text.trim();
    final String roleDetails = _roleDetailsC.text.trim();

    try {
      // 1) Friendly pre-check (on primary auth): does this email already exist?
      final List<String> methods =
      await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
      if (methods.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That email already has an account.')),
        );
        _creating = false;
        return;
      }

      // 2) Get or create ONE secondary FirebaseAuth (so admin stays signed in)
      final FirebaseAuth auth2 = await _ensureSecondaryAuth();

      // 3) Create the new Auth user on secondary app
      final UserCredential userCred =
      await auth2.createUserWithEmailAndPassword(email: email, password: pwd);

      // 4) Set display name (if user not null)
      if (userCred.user != null) {
        await userCred.user!.updateDisplayName(name);
      }

      // 5) Grab UID
      String uid = '';
      if (userCred.user != null) {
        uid = userCred.user!.uid;
      }

      // 6) Write Firestore doc for this user
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

      // 7) Try to send verification email (best effort)
      bool emailSent = false;
      try {
        if (userCred.user != null) {
          await userCred.user!.sendEmailVerification();
          emailSent = true;
        }
      } catch (e) {
        debugPrint('sendEmailVerification failed: $e');
      }

      // 8) Show message to user
      if (!mounted) {
        _creating = false;
        return;
      }
      if (emailSent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Manager created. Verification email sent.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Manager created. Couldn’t send verification email right now.')));
      }

      // 9) Close the add form
      setState(() {
        _isAdding = false;
      });
    } on FirebaseAuthException catch (e) {
      // Map common auth errors to friendly messages
      String msg = 'Authentication error';
      if (e.code == 'email-already-in-use') {
        msg = 'That email already has an account.';
      } else if (e.code == 'invalid-email') {
        msg = 'Invalid email address.';
      } else if (e.code == 'weak-password') {
        msg = 'Weak password.';
      } else if (e.code == 'operation-not-allowed') {
        msg = 'Email/password sign-in is disabled in Firebase.';
      } else if (e.code == 'network-request-failed') {
        msg = 'Network error. Please check your connection.';
      } else {
        if (e.message != null) {
          msg = e.message!;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      // Any other error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      // Important: sign out only the secondary user (we keep the app)
      try {
        if (_auth2 != null) {
          await _auth2!.signOut();
        }
      } catch (e) {
        // ignore
      }
      _creating = false;
    }
  }

  /* ==========================================================================
    SECTION 4B: SAVE EDITS (update Firestore fields)
    - Updates only: username, contact, roleDetails
  ========================================================================= */

  Future<void> _saveEdits() async {
    if (_selected == null) {
      return;
    }

    // Validate the edit form first
    final FormState? form = _editFormKey.currentState;
    if (form == null) {
      return;
    }
    final bool isValid = form.validate();
    if (!isValid) {
      return;
    }

    // Read updated values
    final String newName = _editNameC.text.trim();
    final String newContact = _editContactC.text.trim();
    final String newRoleDetails = _editRoleDetailsC.text.trim();

    try {
      // Update Firestore
      await FirebaseFirestore.instance
          .collection('UserInformation')
          .doc(_selected!.id)
          .update({
        'username': newName,
        'contact': newContact,
        'roleDetails': newRoleDetails,
      });

      // Update local selected item so right panel shows new values immediately
      setState(() {
        String? tag;
        if (_selected!.isVerified) {
          tag = null;
        } else {
          tag = 'Pending';
        }

        _selected = ManagerItem(
          id: _selected!.id,
          name: newName,
          email: _selected!.email,
          contact: newContact,
          role: _selected!.role,
          isVerified: _selected!.isVerified,
          statusTag: tag,
          roleDetails: newRoleDetails,
        );
        _isEditing = false; // leave edit mode
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  /* ==========================================================================
    SECTION 4C: DELETE (SOFT DELETE)
    - Only allowed if manager has NO facilities assigned
    - We check Facilities where managerName == selected manager's name
  ========================================================================= */

  Future<void> _deleteManager() async {
    if (_selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a manager first')),
      );
      return;
    }

    final String selectedName = _selected!.name;

    try {
      // 1) Check if this manager manages any Facilities
      final QuerySnapshot q = await FirebaseFirestore.instance
          .collection('Facilities')
          .where('managerName', isEqualTo: selectedName)
          .limit(1)
          .get();

      if (q.docs.isNotEmpty) {
        // Block delete
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Make sure the manager have no facility to manage')),
        );
        return;
      }

      // 2) Soft delete: set "deleted" to true
      await FirebaseFirestore.instance
          .collection('UserInformation')
          .doc(_selected!.id)
          .update({'deleted': true});

      // 3) Show a simple dialog
      if (!mounted) {
        return;
      }
      await showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: const Text('Deleted'),
            content: const Text('Manager has been deleted.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // close dialog
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      // 4) Clear selection and exit edit mode
      setState(() {
        _selected = null;
        _isEditing = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  /* ==========================================================================
    SECTION 4D: SECONDARY AUTH (create users without logging out admin)
    - On web we set persistence to NONE to avoid IndexedDB issues
  ========================================================================= */

  Future<FirebaseAuth> _ensureSecondaryAuth() async {
    // If we already created the secondary app/auth, return it
    if (_secApp != null && _auth2 != null) {
      return _auth2!;
    }

    // Try to get an existing app named "secondary"
    try {
      _secApp = Firebase.app('secondary');
    } catch (e) {
      // If not found, create a new one with same options
      _secApp = await Firebase.initializeApp(
        name: 'secondary',
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    // Create an Auth instance for that app
    _auth2 = FirebaseAuth.instanceFor(app: _secApp!);

    // On web: do NOT keep session (temporary only)
    if (kIsWeb) {
      await _auth2!.setPersistence(Persistence.NONE);
    }

    return _auth2!;
  }

  /* ==========================================================================
    SECTION 5: LIFECYCLE (dispose controllers)
  ========================================================================= */

  @override
  void dispose() {
    // Dispose all controllers to free memory
    _search.dispose();
    _nameC.dispose();
    _emailC.dispose();
    _contactC.dispose();
    _pwdC.dispose();
    _roleDetailsC.dispose();
    _editNameC.dispose();
    _editContactC.dispose();
    _editRoleDetailsC.dispose();

    // Call super at the end
    super.dispose();
  }

  /* ==========================================================================
    SECTION 6: UI (build)
    - Top bar
    - Two columns (left: list, right: details)
  ========================================================================= */

  @override
  Widget build(BuildContext context) {
    // Scaffold = basic page layout with appBar and body
    return Scaffold(
      // App bar at the top (your reusable top bar)
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: const WebCustomTopBar(use24HourFormat: true),
      ),

      // Body with layout that can scroll if needed
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Scroll the whole page vertically if needed
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Align(
                  alignment: Alignment.topCenter,
                  // Allow sideways scroll if width is not enough
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 460.w + 24.w + 1200.w),
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ---------------- LEFT: MANAGER LIST BOX ----------------
                          _Box(
                            width: 460.w,
                            height: 965.h,
                            title: 'Manager',
                            header: _SearchHeader(
                              controller: _search,
                              hint: 'Search',
                              onChanged: (text) {
                                setState(() {
                                  // just rebuild to apply _applySearch
                                });
                              },
                              onAdd: _onAddManager,
                            ),
                            // The scrollable content inside the box
                            child: StreamBuilder<List<ManagerItem>>(
                              stream: _managerStream,
                              builder: (context, snap) {
                                if (!snap.hasData) {
                                  return const Center(child: CircularProgressIndicator());
                                }

                                final List<ManagerItem> data = _applySearch(snap.data!);
                                if (data.isEmpty) {
                                  return const _EmptyCenter(text: 'empty');
                                }

                                return ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  itemCount: data.length,
                                  separatorBuilder: (_, __) => SizedBox(height: 8.h),
                                  itemBuilder: (context, i) {
                                    final ManagerItem item = data[i];
                                    return _ListTileCard(
                                      label: item.name,
                                      onTap: () {
                                        setState(() {
                                          _selected = item;
                                          _isEditing = false;
                                          _editNameC.text = item.name;
                                          _editContactC.text = item.contact;
                                          if (item.roleDetails == null) {
                                            _editRoleDetailsC.text = '';
                                          } else {
                                            _editRoleDetailsC.text = item.roleDetails!;
                                          }
                                        });
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ),

                          SizedBox(width: 24.w), // space between columns

                          // ---------------- RIGHT: DETAILS BOX ----------------
                          _Box(
                            width: 1200.w,
                            height: 965.h,
                            title: 'Details',
                            header: null,
                            child: SingleChildScrollView(
                              padding: EdgeInsets.only(right: 8.w, bottom: 8.h),
                              child: _buildRightPanelChild(),
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

  // Decide what to show on the right panel (add form / idle / details)
  Widget _buildRightPanelChild() {
    // If in "Add" mode, show the add form
    if (_isAdding) {
      return _buildAddForm();
    }

    // If nothing selected, show idle text
    if (_selected == null) {
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

    // If a row is selected, show its details (with edit mode switch)
    return KeyedSubtree(
      key: ValueKey(_selected!.id),
      child: _buildSelectedDetails(_selected!),
    );
  }

  /* ==========================================================================
    SECTION 7: SMALL UI HELPERS (fields and selected details)
  ========================================================================= */

  // Build one read-only text field row with a label
  Widget _roField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
        SizedBox(height: 6.h),
        TextFormField(
          initialValue: value,
          enabled: false, // read-only
          decoration: InputDecoration(
            isDense: true,
            disabledBorder: const OutlineInputBorder(
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

  // Build one editable text field row with a label
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

  // Build the right panel (view/edit of a selected Manager) + facilities list
  Widget _buildSelectedDetails(ManagerItem item) {
    // Build the main content inside a Column.
    // If editing, we wrap with a Form to use _editFormKey.
    final List<Widget> children = [];

    children.add(SizedBox(height: 12.h));

    // Name (edit or read-only)
    if (_isEditing) {
      children.add(_editField(
        'Manager Name',
        _editNameC,
        validator: (v) {
          if (v == null) {
            return 'Name cannot be empty';
          }
          final String t = v.trim();
          if (t.isEmpty) {
            return 'Name cannot be empty';
          }
          return null;
        },
      ));
    } else {
      children.add(_roField('Manager Name', item.name));
    }

    // Email (read-only)
    children.add(_roField('Manager Email', item.email));

    // Contact (edit or read-only)
    if (_isEditing) {
      children.add(_editField(
        'Manager Contact',
        _editContactC,
        type: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        validator: (v) {
          if (v == null) {
            return 'Contact cannot be empty';
          }
          final String t = v.trim();
          if (t.isEmpty) {
            return 'Contact cannot be empty';
          }
          final RegExp onlyDigits = RegExp(r'^\d+$');
          if (!onlyDigits.hasMatch(t)) {
            return 'Digits only';
          }
          return null;
        },
      ));
    } else {
      children.add(_roField('Manager Contact', item.contact));
    }

    // Role (read-only)
    children.add(_roField('Manager Role', item.role));

    // Role Details (edit or read-only)
    if (_isEditing) {
      children.add(_editField('Role Details', _editRoleDetailsC));
    } else {
      final String roleDetailsText = (item.roleDetails == null) ? '-' : item.roleDetails!;
      children.add(_roField('Role Details', roleDetailsText));
    }

    // Status (read-only)
    final String statusText = item.isVerified ? 'Active' : 'Inactive';
    children.add(_roField('Status', statusText));

    // Header for facilities
    children.add(Text('Manage Facility',
        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)));
    children.add(SizedBox(height: 8.h));

    // Facilities list that this manager manages
    // Facilities list that this manager manages (hide deleted == true)
    children.add(
      StreamBuilder<QuerySnapshot>(
        // Listen only by managerName (simple query)
        stream: FirebaseFirestore.instance
            .collection('Facilities')
            .where('managerName', isEqualTo: item.name)
            .snapshots(),
        builder: (context, snap) {
          // If still loading, show progress
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            );
          }

          // Get all docs first
          final List<QueryDocumentSnapshot> allDocs = snap.data!.docs;

          // Filter out facilities that are marked deleted == true
          // NOTE: If 'deleted' field is missing, we treat it as NOT deleted (still active).
          final List<QueryDocumentSnapshot> activeDocs = [];
          for (final d in allDocs) {
            final Object? raw = d.data();
            bool isDeleted = false;

            if (raw is Map<String, dynamic>) {
              if (raw.containsKey('deleted') && raw['deleted'] == true) {
                isDeleted = true;
              }
            }

            if (!isDeleted) {
              activeDocs.add(d);
            }
          }

          // If no active facility, show "No facility to manage"
          if (activeDocs.isEmpty) {
            return Padding(
              padding: EdgeInsets.only(top: 6.h),
              child: Text(
                'No facility to manage',
                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500),
              ),
            );
          }

          // Build tiles for active facilities only
          final List<Widget> items = [];
          for (final d in activeDocs) {
            String facName = 'Unnamed';

            final Object? raw = d.data();
            if (raw is Map<String, dynamic>) {
              // Prefer 'facilityName', fallback to 'name'
              if (raw.containsKey('facilityName') && raw['facilityName'] != null) {
                facName = raw['facilityName'].toString();
              } else {
                if (raw.containsKey('name') && raw['name'] != null) {
                  facName = raw['name'].toString();
                }
              }
            }

            items.add(
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

          return Column(children: items);
        },
      ),
    );


    // Action buttons at the bottom-right
    children.add(SizedBox(height: 20.h));
    final List<Widget> actionButtons = [];

    if (_isEditing) {
      // Delete button (confirm dialog)
      actionButtons.add(
        TextButton(
          onPressed: () async {
            final bool? confirm = await showDialog<bool>(
              context: context,
              builder: (_) {
                return AlertDialog(
                  title: const Text('Confirm delete'),
                  content: const Text('Are you sure you want to delete this manager?'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop(false);
                      },
                      child: const Text('No'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () {
                        Navigator.of(context).pop(true);
                      },
                      child: const Text('Yes'),
                    ),
                  ],
                );
              },
            );
            if (confirm == true) {
              await _deleteManager();
            }
          },
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Delete'),
        ),
      );

      actionButtons.add(SizedBox(width: 8.w));

      // Cancel button (leave edit mode)
      actionButtons.add(
        TextButton(
          onPressed: () {
            setState(() {
              _isEditing = false;
            });
          },
          child: const Text('Cancel'),
        ),
      );

      actionButtons.add(SizedBox(width: 8.w));

      // Confirm button (save)
      actionButtons.add(
        ElevatedButton(
          onPressed: _saveEdits,
          child: const Text('Confirm'),
        ),
      );
    } else {
      // Edit button (enter edit mode)
      actionButtons.add(
        ElevatedButton(
          onPressed: () {
            _editNameC.text = item.name;
            _editContactC.text = item.contact;
            if (item.roleDetails == null) {
              _editRoleDetailsC.text = '';
            } else {
              _editRoleDetailsC.text = item.roleDetails!;
            }
            setState(() {
              _isEditing = true;
            });
          },
          child: const Text('Edit'),
        ),
      );
    }

    final Widget contentColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );

    // If editing, wrap with Form; otherwise just return the Column
    if (_isEditing) {
      return Padding(
        padding: EdgeInsets.all(12.w),
        child: Form(
          key: _editFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              contentColumn,
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actionButtons,
              ),
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
            contentColumn,
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actionButtons,
            ),
          ],
        ),
      );
    }
  }

  /* ==========================================================================
    SECTION 8: ADD FORM UI (simple and clear)
  ========================================================================= */

  // Build a reusable validated field for the add form
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

  // Build the "Add Manager" form
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

            // Name (required)
            _vField(
              'Manager Name',
              _nameC,
              validator: (v) {
                if (v == null) {
                  return 'Name cannot be empty';
                }
                final String t = v.trim();
                if (t.isEmpty) {
                  return 'Name cannot be empty';
                }
                return null;
              },
            ),

            // Email (required + simple pattern)
            _vField(
              'Manager Email',
              _emailC,
              type: TextInputType.emailAddress,
              validator: (v) {
                if (v == null) {
                  return 'Email cannot be empty';
                }
                final String t = v.trim();
                if (t.isEmpty) {
                  return 'Email cannot be empty';
                }
                if (!_emailRegex.hasMatch(t)) {
                  return 'Enter a valid email';
                }
                return null;
              },
            ),

            // Contact (required + digits only)
            _vField(
              'Manager Contact',
              _contactC,
              type: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (v == null) {
                  return 'Contact cannot be empty';
                }
                final String t = v.trim();
                if (t.isEmpty) {
                  return 'Contact cannot be empty';
                }
                final RegExp onlyDigits = RegExp(r'^\d+$');
                if (!onlyDigits.hasMatch(t)) {
                  return 'Digits only';
                }
                return null;
              },
            ),

            // Password (required + strength rule + eye toggle)
            _vField(
              'Password',
              _pwdC,
              obscure: _hidePwd,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _hidePwd = !_hidePwd;
                  });
                },
                icon: Icon(_hidePwd ? Icons.visibility : Icons.visibility_off),
              ),
              validator: (v) {
                if (v == null) {
                  return 'Password cannot be empty';
                }
                final String t = v;
                if (t.isEmpty) {
                  return 'Password cannot be empty';
                }
                if (!_isPasswordStrong(t)) {
                  return 'Password must be at least 8 characters, include 1 uppercase letter and 1 special character';
                }
                return null;
              },
            ),

            // Role (read-only)
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

            // Role details (optional)
            _vField('Role Details', _roleDetailsC),

            Row(
              children: [
                ElevatedButton(
                  onPressed: _createManager,
                  child: const Text('Create'),
                ),
                SizedBox(width: 12.w),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _isAdding = false;
                    });
                  },
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

/* ============================================================================
  SECTION 9: REUSABLE UI PARTS (Box, SearchHeader, ListTileCard, EmptyCenter)
============================================================================ */

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
          if (header != null) header!,
          if (header != null) SizedBox(height: 8.h),
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
        // Search field (Expanded to use remaining width)
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
        // Small square outlined add button
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
        style: TextStyle(fontSize: 14.sp, color: Colors.black.withOpacity(0.6)),
      ),
    );
  }
}
