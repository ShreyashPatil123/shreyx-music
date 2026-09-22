import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/vibe_provider.dart';
import '../../theme/app_theme.dart';
import 'vibe_room_screen.dart';

class VibeHomeSheet extends StatefulWidget {
  const VibeHomeSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VibeHomeSheet(),
    );
  }

  @override
  State<VibeHomeSheet> createState() => _VibeHomeSheetState();
}

class _VibeHomeSheetState extends State<VibeHomeSheet> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final TextEditingController _joinCodeCtrl = TextEditingController();
  final TextEditingController _joinNameCtrl = TextEditingController();
  final TextEditingController _hostRoomNameCtrl = TextEditingController(text: "Late Night Vibe");
  final TextEditingController _hostNameCtrl = TextEditingController();

  bool _isCreatingOrJoining = false;
  String? _joinCodeError;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    const defaultName = "MusicLover";
    _joinNameCtrl.text = defaultName;
    _hostNameCtrl.text = defaultName;
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _joinCodeCtrl.dispose();
    _joinNameCtrl.dispose();
    _hostRoomNameCtrl.dispose();
    _hostNameCtrl.dispose();
    super.dispose();
  }

  void _navigateToRoom(BuildContext context) {
    if (_hasNavigated) return;
    _hasNavigated = true;
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      VibeRoomScreen.push(context);
    }
  }

  Future<void> _handleJoin(VibeProvider vibe) async {
    final code = _joinCodeCtrl.text.trim().toUpperCase();
    final name = _joinNameCtrl.text.trim();

    if (code.length != 6) {
      setState(() {
        _joinCodeError = 'Room code must be exactly 6 characters';
      });
      return;
    }

    setState(() {
      _joinCodeError = null;
      _isCreatingOrJoining = true;
    });

    try {
      await vibe.joinRoom(roomCode: code, userName: name.isNotEmpty ? name : 'Guest');
      if (mounted) {
        setState(() => _isCreatingOrJoining = false);
      }
    } catch (e) {
      if (mounted) {
        final err = e.toString().replaceAll("Exception: ", "").replaceAll("TimeoutException after 0:00:15.000000: ", "");
        setState(() {
          _isCreatingOrJoining = false;
          _joinCodeError = err;
        });
      }
    }
  }

  Future<void> _handleCreate(VibeProvider vibe) async {
    final roomName = _hostRoomNameCtrl.text.trim();
    final hostName = _hostNameCtrl.text.trim();

    setState(() => _isCreatingOrJoining = true);
    try {
      await vibe.createRoom(
        hostName: hostName.isNotEmpty ? hostName : 'Host',
        roomName: roomName.isNotEmpty ? roomName : 'Party Room',
      );
      if (mounted) {
        setState(() => _isCreatingOrJoining = false);
        _navigateToRoom(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreatingOrJoining = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.bgElevated,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.sensors_off_rounded, color: Colors.orangeAccent),
                SizedBox(width: 8),
                Text('Party Unavailable', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            content: Text(
              e.toString().replaceAll("Exception: ", ""),
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            actions: [
              TextButton(
                child: const Text('OK', style: TextStyle(color: AppTheme.neon)),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vibe = context.watch<VibeProvider>();

    // Listen to status change: if room joined, navigate to room
    if (vibe.isInRoom && !_isCreatingOrJoining) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _navigateToRoom(context);
        }
      });
    }

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppTheme.borderHairline)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Bar
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.neon.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.sensors_rounded, color: AppTheme.neon, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'ShreyX Vibe',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Listen Together • In Real-Time Sync',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white60),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Active Room Card if already joined
                if (vibe.isInRoom) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.bgElevated,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.neon.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppTheme.neon, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Active Room: ${vibe.room?.code ?? ""}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${vibe.room?.name ?? "Party"} • ${vibe.room?.members.length ?? 0} members',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.neon,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                                label: const Text('Open Room', style: TextStyle(fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  VibeRoomScreen.push(context);
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.danger,
                                side: const BorderSide(color: AppTheme.danger),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Leave'),
                              onPressed: () => vibe.leaveRoom(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else if (vibe.isWaitingApproval) ...[
                  // Waiting Room Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.bgElevated,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(color: AppTheme.cyan),
                        const SizedBox(height: 16),
                        const Text(
                          'Waiting for Host Approval',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'The host has been notified. You will join automatically once approved.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 14),
                        TextButton(
                          child: const Text('Cancel Request', style: TextStyle(color: AppTheme.danger)),
                          onPressed: () => vibe.leaveRoom(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  // Tab Selector: Join vs Host
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.bgElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderHairline),
                    ),
                    child: TabBar(
                      controller: _tabCtrl,
                      indicator: BoxDecoration(
                        color: AppTheme.neon,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      labelColor: Colors.black,
                      unselectedLabelColor: AppTheme.textSecondary,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      tabs: const [
                        Tab(text: 'Join a Party'),
                        Tab(text: 'Host a Party'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    height: 275,
                    child: TabBarView(
                      controller: _tabCtrl,
                      children: [
                        // --- Join Party View ---
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _joinCodeCtrl,
                              textCapitalization: TextCapitalization.characters,
                              maxLength: 6,
                              buildCounter: (_, {required currentLength, maxLength, required isFocused}) => null,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(6),
                                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                              ],
                              onChanged: (val) {
                                if (_joinCodeError != null) {
                                  setState(() => _joinCodeError = null);
                                }
                              },
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 3,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                labelText: '6-Digit Room Code',
                                labelStyle: const TextStyle(color: AppTheme.textMuted, letterSpacing: 0),
                                hintText: 'e.g. VIBE88',
                                hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 3),
                                prefixIcon: const Icon(Icons.pin_rounded, color: AppTheme.neon, size: 20),
                                errorText: _joinCodeError,
                                errorStyle: const TextStyle(color: AppTheme.danger, fontSize: 11),
                                filled: true,
                                fillColor: AppTheme.bgElevated,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.borderHairline),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _joinNameCtrl,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                labelText: 'Your Nickname',
                                labelStyle: const TextStyle(color: AppTheme.textMuted),
                                prefixIcon: const Icon(Icons.person_outline_rounded, color: AppTheme.neon, size: 20),
                                filled: true,
                                fillColor: AppTheme.bgElevated,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.borderHairline),
                                ),
                              ),
                            ),
                            const Spacer(),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.neon,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: _isCreatingOrJoining ? null : () => _handleJoin(vibe),
                              child: _isCreatingOrJoining
                                  ? const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          'Connecting to ShreyX Vibe...',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black),
                                        ),
                                      ],
                                    )
                                  : const Text(
                                      'Enter Party Room',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                            ),
                          ],
                        ),

                        // --- Host Party View ---
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: AppTheme.bgElevated,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.borderHairline),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.public_rounded, size: 15, color: AppTheme.neon),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Listen together in real time with friends anywhere.',
                                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextField(
                              controller: _hostRoomNameCtrl,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                labelText: 'Party Room Name',
                                labelStyle: const TextStyle(color: AppTheme.textMuted),
                                hintText: 'e.g. Chill Session',
                                prefixIcon: const Icon(Icons.celebration_rounded, color: AppTheme.neon, size: 20),
                                filled: true,
                                fillColor: AppTheme.bgElevated,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.borderHairline),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _hostNameCtrl,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                labelText: 'Host Name',
                                labelStyle: const TextStyle(color: AppTheme.textMuted),
                                prefixIcon: const Icon(Icons.badge_outlined, color: AppTheme.neon, size: 20),
                                filled: true,
                                fillColor: AppTheme.bgElevated,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.borderHairline),
                                ),
                              ),
                            ),
                            const Spacer(),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.neon,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: _isCreatingOrJoining ? null : () => _handleCreate(vibe),
                              child: _isCreatingOrJoining
                                  ? const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          'Connecting to ShreyX Vibe...',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black),
                                        ),
                                      ],
                                    )
                                  : const Text(
                                      'Start Party as Host',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                // Security & Privacy note
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.shield_outlined, size: 13, color: AppTheme.textMuted),
                      SizedBox(width: 5),
                      Text(
                        'Anonymous • Audio streams on your device • Zero accounts',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
                      ),
                    ],
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
