import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../../core/constants/api_constants.dart';
import '../../core/network/api_service.dart';
import '../../core/network/token_storage.dart';
import '../../core/theme/app_theme.dart';

class AppChatScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String patientName;
  final String patientId;
  final String professionalId;
  final String professionalType;

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
  bool _sending = false;
  String? _error;
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    try {
      final res = await _api.getChatHistory(widget.sessionId);
      final data = res.data;
      if (data is Map && data['success'] == true) {
        _messages = (data['messages'] is List)
            ? (data['messages'] as List)
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : <Map<String, dynamic>>[];
      } else {
        throw Exception(
          data is Map
              ? (data['error'] ?? data['message'] ?? 'Unable to load chat')
              : 'Unable to load chat',
        );
      }

      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) {
        throw Exception('Authentication required');
      }

      _socket = IO.io(
        ApiConstants.socketBaseUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .setAuth({'token': token})
            .setExtraHeaders({'Authorization': 'Bearer $token'})
            .enableReconnection()
            .build(),
      );

      _socket!.onConnect((_) {
        if (kDebugMode) {
          debugPrint('Professional App: authenticated socket connected');
        }
        _socket!.emit('join_chat', {'sessionId': widget.sessionId});
      });

      _socket!.onConnectError((error) {
        if (!mounted) return;
        setState(() => _error = 'Secure chat connection failed');
        if (kDebugMode) debugPrint('Socket connect error: $error');
      });
      _socket!.on('chat_error', (data) {
        if (!mounted) return;
        final message = data is Map ? data['error'] : data;
        setState(() => _error = (message ?? 'Chat request failed').toString());
      });
      _socket!.on('receive_message', _handleIncomingMessage);
      _socket!.connect();
    } catch (error) {
      if (mounted) setState(() => _error = _cleanError(error));
      if (kDebugMode) debugPrint('Error initializing chat: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _handleIncomingMessage(dynamic data) {
    try {
      final decoded = data is String ? jsonDecode(data) : data;
      if (decoded is! Map) return;
      final message = Map<String, dynamic>.from(decoded);
      final id = (message['_id'] ?? '').toString();
      final duplicate = _messages.any(
        (row) => id.isNotEmpty && (row['_id'] ?? '').toString() == id,
      );
      if (duplicate || !mounted) return;
      setState(() {
        _messages.add(message);
        _sending = false;
        _error = null;
      });
      _scrollToBottom();
    } catch (error) {
      if (kDebugMode) debugPrint('Receive message parse error: $error');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _sendMessage() {
    final text = _msgController.text.trim();
    final socket = _socket;
    if (text.isEmpty || socket == null || !socket.connected || _sending) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    // SECURITY: senderId and senderType are intentionally not supplied.
    // Backend B1 derives both from the authenticated Socket.IO JWT.
    socket.emit('send_message', {
      'sessionId': widget.sessionId,
      'content': text,
      'messageType': 'text',
    });
    _msgController.clear();
  }

  String _senderId(Map<String, dynamic> message) {
    final raw = message['senderId'];
    if (raw is Map) return (raw['_id'] ?? raw['id'] ?? '').toString();
    return (raw ?? '').toString();
  }

  String _cleanError(Object error) =>
      error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  @override
  void dispose() {
    _socket?.off('receive_message');
    _socket?.off('chat_error');
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
            Text(
              widget.patientName,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              'Patient',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
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
                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: AppTheme.error.withValues(alpha: 0.08),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppTheme.error),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = _senderId(msg) == widget.professionalId;
                      final createdAt = DateTime.tryParse(
                        (msg['createdAt'] ?? '').toString(),
                      )?.toLocal();

                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isMe ? AppTheme.primary : Colors.white,
                                borderRadius: BorderRadius.circular(16).copyWith(
                                  bottomRight: isMe
                                      ? const Radius.circular(0)
                                      : const Radius.circular(16),
                                  bottomLeft: !isMe
                                      ? const Radius.circular(0)
                                      : const Radius.circular(16),
                                ),
                                border: isMe
                                    ? null
                                    : Border.all(color: AppTheme.border),
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              child: Text(
                                (msg['content'] ?? '').toString(),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  color: isMe
                                      ? Colors.white
                                      : AppTheme.textPrimary,
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
                                createdAt == null
                                    ? ''
                                    : DateFormat('hh:mm a').format(createdAt),
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
                  padding: const EdgeInsets.all(16).copyWith(
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                  ),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _msgController,
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: GoogleFonts.plusJakartaSans(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: AppTheme.surface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _sendMessage,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: _sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Iconsax.send_1,
                                  color: Colors.white,
                                  size: 20,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
