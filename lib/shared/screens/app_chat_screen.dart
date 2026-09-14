import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../core/theme/app_theme.dart';
import '../../core/network/api_service.dart';
import '../../core/network/token_storage.dart';
import '../../core/constants/api_constants.dart';

class AppChatScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String patientName;
  final String patientId;
  final String professionalId;
  final String professionalType; // e.g. 'doctor'

  const AppChatScreen({
    super.key,
    required this.sessionId,
    required this.patientName,
    required this.patientId,
    required this.professionalId,
    required this.professionalType,
  });

  @override
  ConsumerState<AppChatScreen> createState() => _AppChatScreenState();
}

class _AppChatScreenState extends ConsumerState<AppChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApiService _api = ApiService();
  
  IO.Socket? _socket;
  bool _loading = true;
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    try {
      // 1. Fetch History
      final res = await _api.getChatHistory(widget.sessionId);
      if (res.data['success']) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(res.data['messages'] ?? []);
        });
      }
      
      // 2. Connect Socket
      final token = await TokenStorage.getToken();
      if (token == null) return;
      
      final socketUrl = ApiConstants.socketBaseUrl;

      _socket = IO.io(socketUrl, IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .build());

      _socket!.onConnect((_) {
        if (kDebugMode) debugPrint('Professional App: Socket connected');
        _socket!.emit('join_chat', {'sessionId': widget.sessionId});
      });

      _socket!.onDisconnect((_) { if (kDebugMode) debugPrint('Professional App: Socket disconnected'); });
      _socket!.onConnectError((err) { if (kDebugMode) debugPrint('Professional App: Socket connection error: $err'); });
      _socket!.onError((err) { if (kDebugMode) debugPrint('Professional App: Socket error: $err'); });

      _socket!.on('receive_message', (data) {
        if (kDebugMode) debugPrint('New chat message received');
        try {
          Map<String, dynamic> msgData;
          if (data is String) {
             msgData = Map<String, dynamic>.from(jsonDecode(data));
          } else {
             msgData = Map<String, dynamic>.from(data);
          }
          
          if (mounted) {
            setState(() {
              // Check for duplicate in case of server echoing back
              final isDuplicate = _messages.any((m) => 
                (m['_id'] != null && m['_id'] == msgData['_id']) || 
                (m['content'] == msgData['content'] && m['senderId'] == msgData['senderId'] && 
                 DateTime.now().difference(DateTime.tryParse(m['createdAt']?.toString() ?? '') ?? DateTime.now()).inSeconds < 2)
              );
              
              if (!isDuplicate) {
                _messages.add(msgData);
              }
            });
            _scrollToBottom();
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Receive message parse error: $e');
        }
      });

      _socket!.connect();

    } catch (e) {
      if (kDebugMode) debugPrint('Error initializing chat: $e');
    } finally {
      setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _sendMessage() {
    final text = _msgController.text.trim();
    if (text.isEmpty || _socket == null) return;

    final msgData = {
      'sessionId': widget.sessionId,
      'senderId': widget.professionalId,
      'senderType': widget.professionalType,
      'content': text,
      'messageType': 'text',
      'createdAt': DateTime.now().toIso8601String(),
    };

    // Add locally for instant feedback
    setState(() {
      _messages.add(msgData);
    });
    _scrollToBottom();

    _socket!.emit('send_message', msgData);
    _msgController.clear();
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.patientName, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            Text('Patient', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final senderRaw = msg['senderId'];
                      final senderId = senderRaw is Map ? (senderRaw['_id'] ?? '') : (senderRaw?.toString() ?? '');
                      final isMe = senderId == widget.professionalId;
                      
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isMe ? AppTheme.primary : Colors.white,
                                borderRadius: BorderRadius.circular(16).copyWith(
                                  bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
                                  bottomLeft: !isMe ? const Radius.circular(0) : const Radius.circular(16),
                                ),
                                border: isMe ? null : Border.all(color: AppTheme.border),
                                boxShadow: [
                                  if (isMe) BoxShadow(color: AppTheme.primary.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4)),
                                ]
                              ),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              child: Text(
                                msg['content'] ?? '',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  color: isMe ? Colors.white : AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(
                                left: isMe ? 0 : 8,
                                right: isMe ? 8 : 0,
                                bottom: 12,
                              ),
                              child: Text(
                                msg['createdAt'] != null ? DateFormat('hh:mm a').format(DateTime.parse(msg['createdAt']).toLocal()) : '',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16).copyWith(bottom: MediaQuery.of(context).padding.bottom + 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _msgController,
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: GoogleFonts.plusJakartaSans(color: AppTheme.textSecondary, fontSize: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                            filled: true,
                            fillColor: AppTheme.surface,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _sendMessage,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                          child: const Icon(Iconsax.send_1, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
    );
  }
}
