import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'web_top_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Category & Facility modules (each owns LEFT list + RIGHT details panel)
import 'web_category_actions.dart';   // CategoryLeftList, CategoryRightPanel, CatView
import 'web_facility_actions.dart';   // FacilityLeftList, FacilityRightPanel, FacView

/// Which right panel is currently visible (or none)
enum ActivePanel { idle, category, facility }

class FacilitiesPage extends StatefulWidget {
  const FacilitiesPage({Key? key}) : super(key: key);

  @override
  State<FacilitiesPage> createState() => _FacilitiesPageState();
}

class _FacilitiesPageState extends State<FacilitiesPage> {
  // ---------- Left lists' search controllers ----------
  final TextEditingController _catSearch = TextEditingController();
  final TextEditingController _facSearch = TextEditingController();

  // ---------- Selected category snapshot (lightweight, for panel header/fields) ----------
  String? _catId;        // null means nothing selected / just added then closed
  String _catName = '';  // simple string (kept in sync by right panel callbacks)
  bool _catAvailable = true;

  // ---------- Selected facility snapshot (we pass the map to the panel for view/edit) ----------
  String? _facId;                      // null means nothing selected / just added then closed
  Map<String, dynamic>? _facData;      // kept as-is; right panel can merge changed fields and return

  // ---------- Which right panel is open + initial subview for each panel ----------
  ActivePanel _active = ActivePanel.idle;
  CatView _catInitial = CatView.view;
  FacView _facInitial = FacView.view;

  // ---------- LEFT callbacks: what to show on the RIGHT ----------
  // Open Category panel in ADD mode when "+" is clicked on the Category list
  void _openAddCategory() {
    setState(() {
      _active = ActivePanel.category;
      _catInitial = CatView.add;
    });
  }

  // When a category list row is tapped → open Category panel in VIEW mode
  void _selectCategory(String id, String name, bool available) {
    setState(() {
      _catId = id;
      _catName = name;
      _catAvailable = available;
      _active = ActivePanel.category;
      _catInitial = CatView.view;
    });
  }

  // Open Facility panel in ADD mode when "+" is clicked on the Facility list
  void _openAddFacility() {
    setState(() {
      _active = ActivePanel.facility;
      _facInitial = FacView.add;
    });
  }

  // When a facility list row is tapped → open Facility panel in VIEW mode
  void _selectFacility(String id, Map<String, dynamic> data) {
    setState(() {
      _facId = id;
      _facData = data;
      _active = ActivePanel.facility;
      _facInitial = FacView.view;
    });
  }

  // ---------- RIGHT callbacks: close panel / reflect updates ----------
  // Close the right panel (go back to idle)
  void _closeRight() {
    setState(() {
      _active = ActivePanel.idle;
    });
  }

  // Right Category panel notifies this page of changes (rename/toggle/delete)
  void _onCategoryUpdated(String? id, String name, bool available) {
    setState(() {
      _catId = id;
      _catName = name;
      _catAvailable = available;
    });
  }

  // Right Facility panel notifies this page of changes (edit/delete)
  void _onFacilityUpdated(String? id, Map<String, dynamic>? data) {
    setState(() {
      _facId = id;
      _facData = data;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 1) run auto-recover
      await runFacilityHousekeepingOnce(context: context, showToast: false);
      // 2) if a facility is selected, pull its latest snapshot
      await _refreshSelectedFacilityDoc();
    });
  }

  Future<void> _refreshSelectedFacilityDoc() async {
    if (_facId == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('Facilities')
        .doc(_facId!)
        .get();
    if (doc.exists) {
      // push fresh data into the right panel
      _onFacilityUpdated(doc.id, doc.data());
    }
  }


  @override
  void dispose() {
    _catSearch.dispose();
    _facSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Top bar (purely presentational)
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
                // Center the whole grid horizontally
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    // Left(460) + gap(16) + Right(1200) ≈ 1676 → give a tiny headroom
                    constraints: BoxConstraints(maxWidth: 1700.w),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ---------------- LEFT COLUMN ----------------
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Category list panel (search + add + tap → select)
                            CategoryLeftList(
                              width: 460.w,
                              height: 400.h,
                              search: _catSearch,
                              onAddTap: _openAddCategory,
                              onSelect: _selectCategory,
                            ),
                            SizedBox(height: 16.h),
                            // Facility list panel (search + add + tap → select)
                            FacilityLeftList(
                              width: 460.w,
                              height: 550.h,
                              search: _facSearch,
                              onAddTap: _openAddFacility,
                              onSelect: _selectFacility,
                            ),
                          ],
                        ),

                        SizedBox(width: 16.w),

                        // ---------------- RIGHT COLUMN ----------------
                        Builder(
                          builder: (_) {
                            // Show Category details panel
                            if (_active == ActivePanel.category) {
                              return CategoryRightPanel(
                                width: 1200.w,
                                height: 965.h,
                                selectedCatId: _catId,
                                selectedCatName: _catName,
                                selectedCatAvailable: _catAvailable,
                                initialView: _catInitial,
                                onClose: _closeRight,
                                onCategoryUpdated: _onCategoryUpdated,
                              );
                            }

                            // Show Facility details panel
                            if (_active == ActivePanel.facility) {
                              return FacilityRightPanel(
                                width: 1200.w,
                                height: 965.h,
                                selectedFacilityId: _facId,
                                selectedFacilityData: _facData,
                                initialView: _facInitial,
                                onClose: _closeRight,
                                onFacilityUpdated: _onFacilityUpdated,
                              );
                            }

                            // Nothing selected → idle placeholder box on the right
                            return Container(
                              width: 1200.w,
                              height: 965.h,
                              padding: EdgeInsets.all(12.w),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEDDFFF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF8620E2), width: 1),
                              ),
                              child: Center(
                                child: Text(
                                  'Please select or add an item',
                                  style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
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
}
