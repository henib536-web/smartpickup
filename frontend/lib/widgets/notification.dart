import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:test_windows/env.dart';

class NotificationModel {
  final int id;
  final String title;
  final String message;
  bool read;

  NotificationModel({required this.id, required this.title, required this.message, this.read = false});

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['notification_id'] ?? 0,
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      read: json['is_read'] ?? false,
    );
  }
}

class NotificationsWidget extends StatefulWidget {
  final int userId;
  const NotificationsWidget({Key? key, required this.userId}) : super(key: key);

  @override
  State<NotificationsWidget> createState() => _NotificationsWidgetState();
}

class _NotificationsWidgetState extends State<NotificationsWidget> with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  List<NotificationModel> _notifications = [];
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _hideOverlay();
    _animationController.dispose();
    super.dispose();
  }

  void _toggleOverlay() {
    if (_isOpen) {
      _hideOverlay();
    } else {
      _showOverlay();
      _fetchFromDB();
    }
  }

  void _showOverlay() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
    _animationController.forward();
  }

  void _hideOverlay() {
    if (_isOpen) {
      _animationController.reverse().then((_) {
        _overlayEntry?.remove();
        _overlayEntry = null;
        if (mounted) setState(() => _isOpen = false);
      });
    }
  }

  OverlayEntry _createOverlayEntry() {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;

    return OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Background transparent pour fermer en cliquant ailleurs
          GestureDetector(
            onTap: _hideOverlay,
            behavior: HitTestBehavior.translucent,
            child: Container(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              color: Colors.transparent,
            ),
          ),
          Positioned(
            width: 280,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(-280 + size.width, size.height + 10),
              child: _buildDropdownPanel(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchFromDB() async {
    setState(() => _isLoading = true);
    // Update overlay to show loading state if it's already open
    _overlayEntry?.markNeedsBuild();
    
    try {
      final response = await http.get(
        Uri.parse('${Env.baseUrl}/notifications/${widget.userId}'),
        headers: Env.defaultHeaders,
      );
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _notifications = data.map((n) => NotificationModel.fromJson(n)).toList();
            _isLoading = false;
          });
          _overlayEntry?.markNeedsBuild();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _overlayEntry?.markNeedsBuild();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    int unreadCount = _notifications.where((n) => !n.read).length;

    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: _toggleOverlay,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a1a),
            border: Border.all(color: _isOpen ? const Color(0xFFFFCC00) : const Color(0xFF333333)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications, color: Colors.white, size: 20),
              if (unreadCount > 0)
                Positioned(
                  top: -8, right: -8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text('$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownPanel() {
    return FadeTransition(
      opacity: _animationController,
      child: ScaleTransition(
        scale: _scaleAnimation,
        alignment: Alignment.topRight,
        child: Material(
          elevation: 20,
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFF1a1a1a),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF333333)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text("Notifications", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const Divider(color: Color(0xFF333333), height: 1),
                if (_isLoading)
                  const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFFFFCC00)))
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: _notifications.isEmpty 
                      ? const Padding(padding: EdgeInsets.all(20), child: Text("Vide", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _notifications.length,
                          itemBuilder: (context, i) => ListTile(
                            leading: Icon(Icons.info, color: _notifications[i].read ? Colors.grey : const Color(0xFFFFCC00), size: 18),
                            title: Text(_notifications[i].title, style: const TextStyle(color: Colors.white, fontSize: 12)),
                            subtitle: Text(_notifications[i].message, style: const TextStyle(color: Colors.grey, fontSize: 11), maxLines: 2),
                          ),
                        ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}