//---------------------------------------
//
//---------------------------------------


//---------------------------------------
// snack bar
//---------------------------------------
/*
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text('FAQ deleted.', style: TextStyle(fontSize: 13.sp))),
);

//---------------------------------------
// normal elevated button
//---------------------------------------
Row(
column:[
ElevatedButton(
  onPressed: () {

  },
  child: const Text('Button'),
)
]

//---------------------------------------
// normal outline button with navigation page in mobile
//---------------------------------------
   OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AndroidSignUpPage()),
                  );
                },
                navigate for mobile

for web go page
context.go('/webviewrating')


close button
 ElevatedButton(
                  onPressed: () { Navigator.pop(context); },
                  child: Text('Close', style: TextStyle(fontSize: 14.sp)),
                ),
//---------------------------------------
// icon button
//---------------------------------------
icon button
 IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),

//---------------------------------------
// TEXT
//---------------------------------------

        Text(
  'Username',                               // (the text to show)
  textAlign: TextAlign.left,                 // (align text)
  softWrap: true,                            // (wrap long lines)
  overflow: TextOverflow.ellipsis,           // (show "..." if too long)
  style: TextStyle(                          // (text looks)
    fontSize: 14.sp,                         // (text size – scales)
    fontWeight: FontWeight.w600,             // (thickness)
    color: const Color(0xFF111827),          // (text color)
    height: 1.3,                             // (line height multiplier)
    letterSpacing: 0.2,                      // (space between letters)
    decoration: TextDecoration.none,         // (underline/lineThrough/none)
  ),
)

//---------------------------------------
// Text Field
//---------------------------------------

final TextEditingController _usernameController = TextEditingController(); // (hold input text)
String? _usernameError;                                                    // (store error msg or null)

TextField(
  controller: _usernameController,                  // (connect controller)
  keyboardType: TextInputType.text,                 // (keyboard type)
  textInputAction: TextInputAction.done,            // (keyboard "action" button)
  style: TextStyle(fontSize: 14.sp),                // (input text size)
  maxLines: 1,                                      // (single line)
  decoration: InputDecoration(                      // (all input visuals)
    labelText: 'Username',                          // (floating label)
    hintText: 'Enter your username',                // (grey hint)
    helperText: '3–20 characters',                  // (small helper under field)
    errorText: _usernameError,                      // (show red error if not null)
    isDense: true,                                  // (make height a bit compact)

    filled: true,                                   // (enable background color)
    fillColor: const Color(0xFFF9FAFB),             // (background color)

    contentPadding: EdgeInsets.symmetric(           // (inner spacing)
      horizontal: 12.w, vertical: 10.h,
    ),

    prefixIcon: Icon(Icons.person, size: 20.w),     // (icon at left)
    suffixIcon: (_usernameController.text.isNotEmpty)
        ? IconButton(
            icon: Icon(Icons.clear, size: 18.w),    // (clear button)
            onPressed: () {                         // (action when tap)
              _usernameController.clear();          // (empty text)
            },
          )
        : null,

    border: OutlineInputBorder(                     // (baseline border)
      borderRadius: BorderRadius.circular(8.r),     // (rounded corner)
      borderSide: BorderSide(
        color: const Color(0xFF6E00D4), width: 1.5.w, // (purple line)
      ),
    ),
    enabledBorder: OutlineInputBorder(              // (idle border)
      borderRadius: BorderRadius.circular(8.r),
      borderSide: BorderSide(
        color: const Color(0xFF6E00D4), width: 1.5.w,
      ),
    ),
    focusedBorder: OutlineInputBorder(              // (when focused)
      borderRadius: BorderRadius.circular(8.r),
      borderSide: BorderSide(
        color: const Color(0xFF6E00D4), width: 2.w,
      ),
    ),
    errorBorder: OutlineInputBorder(                // (error, not focused)
      borderRadius: BorderRadius.circular(8.r),
      borderSide: BorderSide(color: Colors.red, width: 1.5.w),
    ),
    focusedErrorBorder: OutlineInputBorder(         // (error + focused)
      borderRadius: BorderRadius.circular(8.r),
      borderSide: BorderSide(color: Colors.red, width: 2.w),
    ),
  ),
  onChanged: (v) {                                  // (run when user types)
    // very basic check just to demo errorText usage
    if (v.trim().length < 3) {
      _usernameError = 'Too short';                 // (set error)
    } else {
      _usernameError = null;                        // (clear error)
    }
    // call setState in a StatefulWidget to refresh UI
    // setState(() {});
  },
)

//---------------------------------------
// Text Form Field
//---------------------------------------
Color(0xFFFBFBFF) white


final GlobalKey<FormState> _formKey = GlobalKey<FormState>(); // (form handle)
final TextEditingController _email = TextEditingController();  // (email text)

Form(
  key: _formKey,                                              // (attach key)
  autovalidateMode: AutovalidateMode.onUserInteraction,       // (live check)
  child: TextFormField(
    controller: _email,                                       // (connect)
    keyboardType: TextInputType.emailAddress,                 // (email kb)
    style: TextStyle(fontSize: 14.sp),                        // (text size)
    decoration: InputDecoration(
      labelText: 'Email',                                     // (label)
      hintText: 'name@example.com',                           // (hint)
      filled: true, fillColor: const Color(0xFFF9FAFB),       // (bg color)
      contentPadding: EdgeInsets.symmetric(                   // (padding)
        horizontal: 12.w, vertical: 10.h,
      ),
      enabledBorder: OutlineInputBorder(                      // (idle border)
        borderRadius: BorderRadius.circular(8.r),
        borderSide: BorderSide(color: const Color(0xFF6E00D4), width: 1.2.w),
      ),
      focusedBorder: OutlineInputBorder(                      // (focus border)
        borderRadius: BorderRadius.circular(8.r),
        borderSide: BorderSide(color: const Color(0xFF6E00D4), width: 2.w),
      ),
    ),
    validator: (v) {                                          // (check value)
      if (v == null || v.trim().isEmpty) return 'Email required';
      if (!v.contains('@')) return 'Invalid email';
      return null;                                            // (ok)
    },
  ),
);

// Somewhere on submit:
// if (_formKey.currentState?.validate() == true) { /* proceed */ }

//---------------------------------------
// Container + BoxDecoration
//---------------------------------------

Container(
  width: 1.0.sw,                                  // (full width)
  padding: EdgeInsets.all(12.w),                  // (inner spacing)
  margin: EdgeInsets.only(top: 12.h),             // (outer spacing)
  decoration: BoxDecoration(                      // (box look)
    color: Colors.white,                          // (background color)
    borderRadius: BorderRadius.circular(10.r),    // (rounded corners)
    border: Border.all(                           // (outline)
      color: const Color(0xFFE0E0F5), width: 1.w,
    ),
    boxShadow: [                                  // (soft shadow)
      BoxShadow(
        color: Colors.black.withOpacity(0.05),    // (shadow color)
        blurRadius: 8.w,                          // (softness)
        spreadRadius: 1.w,                        // (grow size)
        offset: Offset(0, 2.h),                   // (move down)
      ),
    ],
  ),
  child: Text(                                    // (content)
    'Panel content here',
    style: TextStyle(fontSize: 14.sp),
  ),
)

//---------------------------------------
// Elevated Button
//---------------------------------------

ElevatedButton(
  onPressed: () { /* handle tap */ },                  // (tap action)
  style: ElevatedButton.styleFrom(                     // (button look)
    backgroundColor: const Color(0xFF6C63FF),         // (bg color)
    foregroundColor: Colors.white,                    // (text/icon color)
    minimumSize: Size(double.infinity, 44.h),         // (min W×H; full width)
    padding: EdgeInsets.symmetric(                     // (inner padding)
      horizontal: 14.w, vertical: 10.h,
    ),
    shape: RoundedRectangleBorder(                     // (corners)
      borderRadius: BorderRadius.circular(8.r),
    ),
    side: BorderSide(                                  // (border line)
      color: const Color(0xFF6C63FF), width: 1.w,
    ),
    elevation: 0,                                      // (no shadow)
    textStyle: TextStyle(                              // (label style)
      fontSize: 14.sp, fontWeight: FontWeight.w600,
    ),
  ),
  child: const Text('Save'),                           // (button label)
)

//---------------------------------------
// Elevated Button
//---------------------------------------

ElevatedButton(
  onPressed: () { /* handle tap */ },                  // (tap action)
  style: ElevatedButton.styleFrom(                     // (button look)
    backgroundColor: const Color(0xFF6C63FF),         // (bg color)
    foregroundColor: Colors.white,                    // (text/icon color)
    minimumSize: Size(double.infinity, 44.h),         // (min W×H; full width)
    padding: EdgeInsets.symmetric(                     // (inner padding)
      horizontal: 14.w, vertical: 10.h,
    ),
    shape: RoundedRectangleBorder(                     // (corners)
      borderRadius: BorderRadius.circular(8.r),
    ),
    side: BorderSide(                                  // (border line)
      color: const Color(0xFF6C63FF), width: 1.w,
    ),
    elevation: 0,                                      // (no shadow)
    textStyle: TextStyle(                              // (label style)
      fontSize: 14.sp, fontWeight: FontWeight.w600,
    ),
  ),
  child: const Text('Save'),                           // (button label)
)

//---------------------------------------
// Outline Button
//---------------------------------------

OutlinedButton(
  onPressed: () { /* handle tap */ },                  // (tap action)
  style: OutlinedButton.styleFrom(                     // (button look)
    foregroundColor: const Color(0xFF6C63FF),         // (text/icon color)
    minimumSize: Size(double.infinity, 44.h),         // (min size)
    padding: EdgeInsets.symmetric(                     // (inner padding)
      horizontal: 14.w, vertical: 10.h,
    ),
    side: BorderSide(                                  // (outline)
      color: const Color(0xFF6C63FF), width: 1.w,
    ),
    shape: RoundedRectangleBorder(                     // (corners)
      borderRadius: BorderRadius.circular(8.r),
    ),
    textStyle: TextStyle(                              // (label style)
      fontSize: 14.sp, fontWeight: FontWeight.w600,
    ),
  ),
  child: const Text('Cancel'),                         // (button label)
)

//---------------------------------------
// Padding
//---------------------------------------

Padding(                                           // (outer space around child)
  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
  child: Text('Hello', style: TextStyle(fontSize: 14.sp)),
)

SizedBox(height: 12.h)                              // (vertical gap)

//---------------------------------------
// Card (something with shadow)
//---------------------------------------

Card(
  shape: RoundedRectangleBorder(                     // (corners)
    borderRadius: BorderRadius.circular(10.r),
  ),
  elevation: 0,                                      // (flat look)
  margin: EdgeInsets.symmetric(vertical: 6.h),       // (outer spacing)
  child: Padding(
    padding: EdgeInsets.all(12.w),                   // (inner spacing)
    child: Row(                                      // (layout inside card)
      mainAxisAlignment: MainAxisAlignment.spaceBetween, // (space between)
      children: [
        Text('Item', style: TextStyle(fontSize: 14.sp)),  // (left text)
        Icon(Icons.chevron_right, size: 20.w),            // (right icon)
      ],
    ),
  ),
)

//---------------------------------------
// Row/Column (for many widget)
//---------------------------------------

Column(
  crossAxisAlignment: CrossAxisAlignment.start,      // (left-align children)
  children: [
    Text('Title', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
    SizedBox(height: 8.h),                            // (gap)
    Text('Subtitle', style: TextStyle(fontSize: 14.sp, color: Colors.black54)),
  ],
)

//---------------------------------------
// Wrap (to wrap the widget when full will go down next row)
//---------------------------------------

Wrap(
  spacing: 8.w,                                      // (gap between items)
  runSpacing: 8.h,                                   // (gap between lines)
  alignment: WrapAlignment.start,                    // (row alignment)
  children: [
    for (int i = 0; i < 10; i++)
      Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),            // (chip bg)
          borderRadius: BorderRadius.circular(20.r),  // (pill shape)
          border: Border.all(color: const Color(0xFF6C63FF), width: 1.w),
        ),
        child: Text('Slot ${i + 1}', style: TextStyle(fontSize: 12.sp)),
      ),
  ],
)


//---------------------------------------
// ListView.separated ( to list out something)
//---------------------------------------

// When used inside Column, add shrinkWrap + NeverScrollable to avoid overflow
ListView.separated(
  itemCount: 8,                                         // (how many rows)
  shrinkWrap: true,                                     // (let list size itself)
  physics: const NeverScrollableScrollPhysics(),        // (parent scrolls)
  separatorBuilder: (_, __) => SizedBox(height: 8.h),   // (gap between rows)
  itemBuilder: (context, i) {
    return Container(
      padding: EdgeInsets.all(12.w),                    // (row padding)
      decoration: BoxDecoration(
        color: Colors.white,                            // (row bg)
        borderRadius: BorderRadius.circular(8.r),       // (corners)
        border: Border.all(color: const Color(0xFFE0E0F5), width: 1.w),
      ),
      child: Text('Row ${i + 1}', style: TextStyle(fontSize: 14.sp)),
    );
  },
)

//---------------------------------------
// GridView.count
//---------------------------------------

GridView.count(
  crossAxisCount: 2,                                   // (2 items per row)
  mainAxisSpacing: 8.h,                                // (vertical gap)
  crossAxisSpacing: 8.w,                               // (horizontal gap)
  childAspectRatio: 1.2,                               // (W/H ratio per tile)
  shrinkWrap: true,                                    // (size to content)
  physics: const NeverScrollableScrollPhysics(),       // (parent scrolls)
  children: List.generate(6, (i) {
    return Container(
      padding: EdgeInsets.all(12.w),                   // (tile padding)
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: const Color(0xFFE0E0F5), width: 1.w),
      ),
      child: Center(
        child: Text('Tile ${i + 1}', style: TextStyle(fontSize: 14.sp)),
      ),
    );
  }),
)


//---------------------------------------
// scroll view , sllow scrolling with constraint box
//---------------------------------------
SingleChildScrollView(                                 // (allow page to scroll)
  padding: EdgeInsets.all(16.w),                       // (page padding)
  child: ConstrainedBox(
    constraints: BoxConstraints(minWidth: 1.0.sw),     // (fill width on web)
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,    // (left-align)
      children: [
        // put your sections here...
      ],
    ),
  ),
)


//---------------------------------------
// Size box
//---------------------------------------

// NOTE: SizedBox has no color/border. For a thin separator use Container:
Container(height: 1.h, color: const Color(0xFFE0E0F5)), // (hairline divider)


// --- vertical gap (most common)
SizedBox(height: 12.h),                         // (add vertical space)

// --- horizontal gap (between Row items)
SizedBox(width: 12.w),                          // (add horizontal space)

// --- fixed size wrapper around any child
SizedBox(
  width: 100.w,                                 // (fix width)
  height: 60.h,                                 // (fix height)
  child: ElevatedButton(                        // (the child to size)
    onPressed: () {},
    child: const Text('Sized Button'),
  ),
)

// --- full-width, fixed-height area (e.g., wide button/image)
SizedBox(
  width: double.infinity,                       // (take all horizontal space)
  height: 44.h,                                 // (fix height)
  child: Center(child: Text('Full width box',   // (center its child)
    style: TextStyle(fontSize: 14.sp),
  )),
)

// --- no size (collapse to zero) – useful to hide something
SizedBox.shrink(),                              // (take 0×0 space)

// --- expand to fill parent both directions
SizedBox.expand(                                // (take all available space)
  child: Container(color: const Color(0xFFEFF6FF)), // (example fill)
)


//---------------------------------------
// normal Align
//---------------------------------------
// --- basic: put child at bottom-right of its available area
Align(
  alignment: Alignment.bottomRight,             // (where to pin the child)
  child: Icon(Icons.star, size: 20.w),          // (the child to position)
)

// --- common: keep a fixed box, then align inside it
Container(
  width: 200.w,                                 // (fixed area width)
  height: 120.h,                                // (fixed area height)
  color: const Color(0xFFF9FAFB),               // (just to see the box)
  child: Align(
    alignment: Alignment.bottomCenter,          // (place at bottom center)
    child: Text('Bottom', style: TextStyle(fontSize: 14.sp)),
  ),
)


// Alignment.center, .centerLeft, .centerRight,
// .topLeft, .topCenter, .topRight,
// .bottomLeft, .bottomCenter, .bottomRight

// --- Align that sizes itself to the child (advanced but handy)
// widthFactor/heightFactor multiply child size to decide Align’s own size.
// If null → Align tries to be as big as possible.
Align(
  alignment: Alignment.centerLeft,              // (left side)
  widthFactor: 1.0,                             // (match child width × 1)
  heightFactor: 1.0,                            // (match child height × 1)
  child: Container(
    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
    color: const Color(0xFFEDE9FE),
    child: Text('Tight box', style: TextStyle(fontSize: 12.sp)),
  ),
)

// --- alternative: Container can also align children directly
Container(
  alignment: Alignment.topRight,                // (align without Align widget)
  child: Icon(Icons.notifications, size: 18.w),
)

//---------------------------------------
// cross axis Align
//---------------------------------------
FOR COLUMN
Container(
  width: 260.w,                                    // (fixed demo width)
  color: const Color(0xFFF3F4F6),                  // (light bg)
  padding: EdgeInsets.all(8.w),                    // (inner padding)
  child: Column(
    mainAxisSize: MainAxisSize.min,                // (only as tall as needed)
    crossAxisAlignment: CrossAxisAlignment.start,  // (LEFT align children on horizontal axis)
    // Try: CrossAxisAlignment.center / end / stretch
    children: [
      Container(
        width: 120.w,                              // (child width)
        height: 28.h,                              // (child height)
        color: const Color(0xFFE0E7FF),            // (box to see alignment)
        alignment: Alignment.center,               // (center the text inside)
        child: Text('Item 1', style: TextStyle(fontSize: 12.sp)),
      ),
    ],
  ),
);

FOR ROW
 // A fixed-height box to observe vertical alignment in a Row
Container(
  width: 1.0.sw,                                   // (full width)
  height: 100.h,                                   // (fixed height so stretch works)
  color: const Color(0xFFF9FAFB),                  // (light bg)
  padding: EdgeInsets.all(8.w),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.start,     // (along horizontal)
    crossAxisAlignment: CrossAxisAlignment.end,     // (BOTTOM align on vertical)
    // Try: CrossAxisAlignment.start (TOP) / center (MIDDLE) / stretch (FILL HEIGHT)
    children: [
      Container(width: 50.w, height: 30.h, color: const Color(0xFFE0E7FF)),
      SizedBox(width: 8.w),
      Container(width: 50.w, height: 50.h, color: const Color(0xFFDDD6FE)),
      SizedBox(width: 8.w),
      Container(width: 50.w, height: 70.h, color: const Color(0xFFC7D2FE)),
    ],
  ),
);
//---------------------------------------
// material with inkwell (come with meterial)
//---------------------------------------

Material(                                                // (enables ripple)
  color: Colors.white,                                   // (card bg)
  borderRadius: BorderRadius.circular(10.r),             // (corners)
  child: InkWell(
    borderRadius: BorderRadius.circular(10.r),           // (ripple shape)
    onTap: () { /* open details */ },                    // (tap action)
    child: Padding(
      padding: EdgeInsets.all(12.w),                     // (inner spacing)
      child: Row(
        children: [
          Icon(Icons.meeting_room, size: 22.w),          // (leading icon)
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Room A-201', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                SizedBox(height: 4.h),
                Text('Capacity: 30', style: TextStyle(fontSize: 12.sp, color: Colors.black54)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20.w),         // (trailing arrow)
        ],
      ),
    ),
  ),
);

//---------------------------------------
// stack with position
//---------------------------------------
Stack(
  children: [
    Container(width: 1.0.sw, height: 120.h, color: const Color(0xFFF9FAFB)), // (base box)
    Positioned(                                          // (pin badge at top-right)
      right: 8.w, top: 8.h,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: const Color(0xFF6C63FF), width: 1.w),
        ),
        child: Text('Open', style: TextStyle(fontSize: 11.sp)),
      ),
    ),
    Positioned(                                          // (pin button at bottom-right)
      right: 12.w, bottom: 12.h,
      child: SizedBox(
        width: 44.w, height: 44.h,
        child: FloatingActionButton(                     // (quick action)
          onPressed: () {}, child: const Icon(Icons.add),
        ),
      ),
    ),
  ],
);

//---------------------------------------
// list tile for tapping
//---------------------------------------
ListTile(
  contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h), // (padding)
  leading: CircleAvatar(radius: 16.r, child: const Icon(Icons.event)),    // (icon/photo)
  title: Text('Your booking', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
  subtitle: Text('19 Nov · 10:00–11:00', style: TextStyle(fontSize: 12.sp)),
  trailing: Icon(Icons.chevron_right, size: 20.w),
  onTap: () { /* open booking */ },
);

//---------------------------------------
// image for asset
//---------------------------------------
ClipRRect(
  borderRadius: BorderRadius.circular(8.r),            // (rounded corners)
  child: Image.asset(
    'assets/room.jpg',                                 // (your path)
    width: 120.w, height: 80.h, fit: BoxFit.cover,     // (size + crop)
  ),
);

//---------------------------------------
// switch and check box
//---------------------------------------
// Switch
SwitchListTile(
  dense: true,                                         // (compact height)
  title: Text('Require manager approval', style: TextStyle(fontSize: 14.sp)),
  value: true, onChanged: (v) { /* set state */ },     // (toggle handler)
);

// Checkbox
CheckboxListTile(
  dense: true,
  title: Text('Send reminder email', style: TextStyle(fontSize: 14.sp)),
  value: false, onChanged: (v) { /* set state */ },
);


//---------------------------------------
// loading
//---------------------------------------
Center(child: SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator(strokeWidth: 2)));


//---------------------------------------
// snack bar
//---------------------------------------
// snackbar (temporary message)
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Saved', style: TextStyle(fontSize: 14.sp)),
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.all(12.w),
  ),
);

//---------------------------------------
// pop up dialog
//---------------------------------------
showDialog(
  context: context,
  barrierDismissible: false,                          // (must choose a button) if true, press outside will off
  builder: (_) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero), // (square corners)
    title: Text('Log out?', style: TextStyle(fontSize: 18.sp)),     // (title)
    content: Text('Are you sure you want to log out?', style: TextStyle(fontSize: 14.sp)),
    actions: [
      TextButton(                                      // (cancel)
        onPressed: () => Navigator.pop(context),
        child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
      ),
      ElevatedButton(                                  // (confirm)
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF0707),    // (red bg)
          foregroundColor: Colors.white,               // (white text)
        ),
        onPressed: () { /* do logout */ Navigator.pop(context); },
        child: Text('Log Out', style: TextStyle(fontSize: 14.sp)),
      ),
    ],
  ),
);

stream builder
/
Widget name;
name = StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
  stream: FirebaseFirestore.instance
      .collection('UserInformation')
      .doc((_userId ?? '').isEmpty ? 'none' : _userId)
      .snapshots(),
  builder: (context, snap) {
    // your requested waiting UI
    if (snap.connectionState == ConnectionState.waiting) {
      return Container(
        width: 1.sw,
        height: 60.h,
        alignment: Alignment.center,
        child: Text('Loading...', style: TextStyle(fontSize: 14.sp)),
      );
    }

    final data  = snap.data?.data();
    final name  = (data?['username'] ?? '...').toString();
    return Text('booked by $name', style: TextStyle(fontSize: 12.sp));
  },
);

void
Future<void> markBookingSeen(String bookingId) async {           // Future<void> for no value
  final ref = FirebaseFirestore.instance                         // get db
      .collection('Bookings')                                    // go to collection
      .doc(bookingId);                                           // choose document

  await ref.set(                                                 // write data
    {'seen': true},                                              // set field
    SetOptions(merge: true),                                     // merge to keep others
  );                                                             // done
}


future builder
 Widget name;
    name = FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.collection('UserInformation')
            .doc((_userId ?? '').isEmpty ? 'none' : _userId)
            .get(),
        builder: (context, snap) {
          final data = snap.data?.data();

          final String name = data?['username']?? "...";
          return Text('booked by $name');
        });


to add id to list after object
can do like -> items.add({...m, 'id': d.id}); but then have to remove it when need to add to database using -> final toSave = Map.of(item)..remove('id');


 */





