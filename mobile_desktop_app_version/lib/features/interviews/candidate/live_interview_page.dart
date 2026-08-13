// lib/features/interviews/candidate/live_interview_page.dart
//
// The live recruiter ↔ candidate call, from either side.
//
// Two states, one screen:
//
//   WAITING — the candidate has arrived before the interviewer. The backend
//             answers 409 until the recruiter opens the call, so this polls and
//             says so plainly. It is a normal part of the flow, not an error,
//             and the wording has to reflect that or people close the app.
//   IN CALL — the Daily room in the same locked-down WebView the Tavus avatar
//             track already uses. Daily's own prebuilt UI provides the lobby,
//             the admit control (owner only) and the camera/mic buttons, so
//             there are no call controls to reimplement here.
//
// The recruiter takes the same screen with `isHost: true`, which opens the call
// instead of waiting for it, and gets the End button — ending deletes the room,
// which ejects the candidate too.

import 'package:flutter/material.dart';

import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/services/twoway_service.dart';
import 'package:talbotiq/shared/widgets/iframe_view.dart';

class LiveInterviewPage extends StatefulWidget {
  final Interview interview;

  /// True for the recruiter, who OPENS the call. The candidate waits for it.
  final bool isHost;

  const LiveInterviewPage({
    super.key,
    required this.interview,
    this.isHost = false,
  });

  @override
  State<LiveInterviewPage> createState() => _LiveInterviewPageState();
}

class _LiveInterviewPageState extends State<LiveInterviewPage> {
  /// How often the candidate re-asks whether the interviewer has arrived.
  ///
  /// Five seconds: fast enough that they are not left staring after the recruiter
  /// joins, slow enough that a candidate waiting ten minutes does not make 600
  /// requests. The call is minted per poll only on SUCCESS, so a wait costs
  /// nothing but the room check.
  static const _pollInterval = Duration(seconds: 5);

  TwoWayGrant? _grant;
  String? _error;
  bool _waiting = false;
  bool _ending = false;

  /// Set on dispose so the poll loop stops instead of running against a screen
  /// nobody is looking at.
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _error = null;
      _waiting = !widget.isHost;
    });

    while (!_disposed) {
      try {
        final grant = widget.isHost
            ? await twoWayService.host(widget.interview.id)
            : await twoWayService.join(widget.interview.id);
        if (_disposed || !mounted) return;
        setState(() {
          _grant = grant;
          _waiting = false;
        });
        return;
      } on TwoWayNotStarted {
        // Expected: the interviewer has not opened the call. Keep waiting.
        if (_disposed || !mounted) return;
        setState(() => _waiting = true);
        await Future<void>.delayed(_pollInterval);
      } catch (e) {
        if (_disposed || !mounted) return;
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _waiting = false;
        });
        return;
      }
    }
  }

  Future<void> _end() async {
    final leaving = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.isHost ? 'End this interview?' : 'Leave the call?'),
        content: Text(
          widget.isHost
              // Ending deletes the room, so it is not just the recruiter leaving.
              ? 'This ends the call for the candidate too. You can then score it '
                  'from the round\'s candidate list.'
              : 'You can rejoin while the interviewer is still in the call.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(widget.isHost ? 'End interview' : 'Leave'),
          ),
        ],
      ),
    );
    if (leaving != true || !mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (!widget.isHost) {
      navigator.pop();
      return;
    }

    setState(() => _ending = true);
    try {
      await twoWayService.complete(widget.interview.id);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(const SnackBar(
        content: Text('Interview ended. Score it from the candidate list.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _ending = false);
      // The call may well have ended for both parties even though recording that
      // failed — say what is actually known.
      messenger.showSnackBar(SnackBar(
        content: Text('Could not end the interview cleanly: '
            '${e.toString().replaceAll('Exception: ', '')}'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // Backing out of a live call by accident is easy and costly, so the
      // confirm runs first.
      canPop: _grant == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _end();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(widget.interview.title),
          actions: [
            if (_grant != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: _ending ? null : _end,
                  icon: Icon(
                      widget.isHost ? Icons.call_end : Icons.logout,
                      size: 18,
                      color: theme.colorScheme.error),
                  label: Text(widget.isHost ? 'End' : 'Leave',
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              ),
          ],
        ),
        body: _body(theme),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    final grant = _grant;
    if (grant != null) return buildIframe(grant.joinUrl);
    if (_error != null) return _errorView(theme);
    return _waitingView(theme);
  }

  Widget _waitingView(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white70),
              const SizedBox(height: 24),
              Text(
                widget.isHost
                    ? 'Opening the call…'
                    : 'Waiting for your interviewer',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                widget.isHost
                    ? 'Setting up the room.'
                    // Says plainly that waiting is normal and that they do not
                    // need to do anything — otherwise people close the app.
                    : '${widget.interview.recruiterName ?? 'Your interviewer'} '
                        'has not started this interview yet. Keep this screen '
                        'open — you will join automatically as soon as they do.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.white70),
              ),
              if (!widget.isHost && _waiting) ...[
                const SizedBox(height: 20),
                Text('Checking every ${_pollInterval.inSeconds} seconds…',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white38)),
              ],
            ],
          ),
        ),
      );

  Widget _errorView(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 44, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                widget.isHost
                    ? 'Could not open the call'
                    : 'Could not join the call',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.white70)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _connect,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
}
