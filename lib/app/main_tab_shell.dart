import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../auth/auth_store.dart';
import '../common/widgets/app_scaffold.dart';
import '../features/actions/actions_page.dart';
import '../features/home/home_page.dart';
import '../features/profile/profile_page.dart';

class MainTabShell extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final int initialIndex;

  const MainTabShell({
    super.key,
    required this.api,
    required this.authStore,
    required this.initialIndex,
  });

  @override
  State<MainTabShell> createState() => MainTabShellState();
}

class MainTabShellState extends State<MainTabShell> {
  late final PageController _pageController;
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _selectedIndex);
  }

  @override
  void didUpdateWidget(covariant MainTabShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex &&
        widget.initialIndex != _selectedIndex) {
      _selectedIndex = widget.initialIndex;
      _pageController.jumpToPage(_selectedIndex);
    }
  }

  Future<void> _onTabSelected(int index) async {
    if (index == _selectedIndex) return;

    setState(() {
      _selectedIndex = index;
    });

    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int index) {
    if (_selectedIndex == index) return;

    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const PageScrollPhysics(),
        onPageChanged: _onPageChanged,
        children: [
          _KeepAliveTab(
            child: HomePage(
              api: widget.api,
              authStore: widget.authStore,
              showBottomNavigationBar: false,
              locationOverride: '/home',
            ),
          ),
          _KeepAliveTab(
            child: ActionsPage(
              api: widget.api,
              authStore: widget.authStore,
              showBottomNavigationBar: false,
              locationOverride: '/actions',
            ),
          ),
          _KeepAliveTab(
            child: ProfilePage(
              api: widget.api,
              authStore: widget.authStore,
              showBottomNavigationBar: false,
              locationOverride: '/profile',
            ),
          ),
        ],
      ),
      bottomNavigationBar: MainNavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onTabSelected,
      ),
    );
  }
}

class _KeepAliveTab extends StatefulWidget {
  final Widget child;

  const _KeepAliveTab({required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
