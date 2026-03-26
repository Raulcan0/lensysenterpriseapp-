// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:applensys/evaluacion/services/chat_service.dart';
import 'package:applensys/evaluacion/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:intl/intl.dart';

class ChatWidgetDrawer extends StatefulWidget {
  const ChatWidgetDrawer({super.key});

  @override
  State<ChatWidgetDrawer> createState() => _ChatWidgetDrawerState();
}

class _ChatWidgetDrawerState extends State<ChatWidgetDrawer> {
  final _chatService = ChatService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late final String _myUserId;
  List<Message> _previousMessages = [];
  StreamSubscription<List<Message>>? _msgSub;

  final Color chatColor = Colors.teal;
  final Color receivedColor = Colors.grey.shade200;

  // =========================
  // 🤖 IA SIMULADA AQUÍ
  // =========================
  int _currentQuestionIndex = 0;
  bool _evaluationFinished = false;

  final List<String> _questions = [
    "¿Cómo percibes que la empresa aplica los Principios Rectores del Modelo Shingo en su día a día?",
    "¿Qué evidencias has encontrado de que los sistemas de gestión realmente generan los comportamientos deseados?",
    "¿Has identificado prácticas que refuercen la cultura de excelencia más allá de los resultados financieros?",
    "¿Cómo evalúas la alineación entre liderazgo, sistemas y herramientas dentro de la organización?",
    "¿Qué tan consistente es la empresa en demostrar respeto por cada persona en sus procesos y decisiones?",
    "¿Has visto ejemplos claros de mejora continua que estén integrados en la cultura, no solo en proyectos aislados?",
    "¿Qué oportunidades detectas para fortalecer la sostenibilidad de la excelencia operativa en esta empresa?  "
  ];

  String _getAIResponse(String userMessage) {
    if (_evaluationFinished) {
      return "Evaluación finalizada.";
    }

    if (_currentQuestionIndex >= _questions.length) {
      _evaluationFinished = true;
      return "Analizando datos...";
    }

    final question = _questions[_currentQuestionIndex];
    _currentQuestionIndex++;

    return question;
  }

  @override
  void initState() {
    super.initState();
    _myUserId = Supabase.instance.client.auth.currentUser!.id;

    _msgSub = _chatService.messageStream().listen((messages) {
      if (mounted && messages.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    });
  }

  Future<void> _tomarYSubirFoto() async {
    final picker = ImagePicker();
    final XFile? foto = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (foto != null) {
      final file = File(foto.path);
      final fileName = 'chat_${DateTime.now().millisecondsSinceEpoch}_$_myUserId.jpg';

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final res = await Supabase.instance.client.storage
          .from('chats')
          .upload(fileName, file);

      Navigator.of(context).pop();

      if (res.isNotEmpty) {
        final url = Supabase.instance.client.storage
            .from('chats')
            .getPublicUrl(fileName);

        await _chatService.sendMessage(_myUserId, url);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo subir la foto')),
        );
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    await _chatService.sendMessage(_myUserId, text);

    _textController.clear();

    // 🤖 RESPUESTA AUTOMÁTICA IA
    final aiResponse = _getAIResponse(text);

    await Future.delayed(const Duration(milliseconds: 600));

    await _chatService.sendMessage("AI_BOT", aiResponse);

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  Widget build(BuildContext context) {
    final drawerWidth = MediaQuery.of(context).size.width.clamp(280, 380).toDouble();

    return Drawer(
      width: drawerWidth,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: chatColor,
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const Text(
                  'Chat IA Evaluación',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.smart_toy, color: Colors.white),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: _chatService.messageStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!;
                final latestMessage = messages.isNotEmpty ? messages.last : null;

                if (_previousMessages.length < messages.length &&
                    latestMessage != null &&
                    latestMessage.userId != _myUserId) {
                  NotificationService.showInstantNotification(
                    id: 1,
                    title: "Evaluación completada",
                    body: "Proceso finalizado",
                    payload: "evaluacion",
                  );
                }

                _previousMessages = List.from(messages);

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(6),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.userId == _myUserId;
                    final isBot = msg.userId == "AI_BOT";
                    final isImage = msg.content.startsWith('http');

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.all(10),
                        constraints: BoxConstraints(maxWidth: drawerWidth * 0.75),
                        decoration: BoxDecoration(
                          color: isMe
                              ? chatColor
                              : isBot
                                  ? Colors.blueGrey.shade100
                                  : receivedColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            isImage
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      msg.content,
                                      fit: BoxFit.cover,
                                      width: drawerWidth * 0.65,
                                    ),
                                  )
                                : Text(
                                    msg.content,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isMe ? Colors.white : Colors.black87,
                                    ),
                                  ),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('HH:mm').format(
                                msg.createdAt is String
                                    ? DateTime.parse(msg.createdAt as String)
                                    : msg.createdAt,
                              ),
                              style: TextStyle(
                                fontSize: 9,
                                color: isMe ? Colors.white70 : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.camera_alt, color: chatColor),
                  onPressed: _tomarYSubirFoto,
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'Mensaje...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: chatColor),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }
}