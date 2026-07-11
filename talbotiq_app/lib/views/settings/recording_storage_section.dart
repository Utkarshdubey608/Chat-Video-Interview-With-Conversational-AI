// lib/views/settings/recording_storage_section.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../models/app_models.dart';
import '../../providers/app_store.dart';
import '../../core/services/recording_service.dart';
import '../../widgets/custom_buttons.dart';
import '../../widgets/custom_inputs.dart';
import '../../widgets/apple_ui.dart';

/// Settings category: cloud recording (Tavus S3 destination) plus the on-device
/// recording library. S3 fields are part of the session config; the local
/// recordings toggle/list use their own store state and save immediately.
class RecordingStorageSection extends StatefulWidget {
  const RecordingStorageSection({super.key});

  @override
  State<RecordingStorageSection> createState() =>
      _RecordingStorageSectionState();
}

class _RecordingStorageSectionState extends State<RecordingStorageSection> {
  final _bucketController = TextEditingController();
  final _regionController = TextEditingController();
  final _roleArnController = TextEditingController();
  bool _enableRecording = false;

  // On-device recording playback.
  final AudioPlayer _audioPlayer = AudioPlayer();
  final RecordingService _recordingService = RecordingService();
  String? _playingId;

  @override
  void initState() {
    super.initState();
    final cfg = Provider.of<AppStore>(context, listen: false).sessionConfig;
    _bucketController.text = cfg.recordingS3BucketName;
    _regionController.text = cfg.recordingS3BucketRegion;
    _roleArnController.text = cfg.awsAssumeRoleArn;
    _enableRecording = cfg.enableRecording;
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingId = null);
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _bucketController.dispose();
    _regionController.dispose();
    _roleArnController.dispose();
    super.dispose();
  }

  // Persists the cloud-recording fields into the shared session config.
  void _saveCloud() {
    final store = Provider.of<AppStore>(context, listen: false);
    store.setSessionConfig(store.sessionConfig.copyWith(
      enableRecording: _enableRecording,
      recordingS3BucketName: _bucketController.text,
      recordingS3BucketRegion: _regionController.text,
      awsAssumeRoleArn: _roleArnController.text,
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Recording settings saved'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  // Toggles playback of a stored recording (stops any other that is playing).
  Future<void> _togglePlay(SavedRecording rec) async {
    if (_playingId == rec.id) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(rec.path));
      if (mounted) setState(() => _playingId = rec.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not play recording: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // Confirms and deletes a stored recording from disk and the store.
  Future<void> _deleteRecording(SavedRecording rec) async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recording?'),
        content: Text('Permanently delete the recording "${rec.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
          CustomButton(
            text: 'Delete',
            variant: ButtonVariant.danger,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    if (_playingId == rec.id) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _playingId = null);
    }
    await _recordingService.deleteFile(rec.path);
    if (!mounted) return;
    Provider.of<AppStore>(context, listen: false).deleteRecording(rec.id);
  }

  // A single row in the local recordings list (play / meta / delete).
  Widget _buildRecordingRow(SavedRecording rec) {
    final theme = Theme.of(context);
    final playing = _playingId == rec.id;
    final sizeMb = (rec.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
    final date = rec.savedAt.contains('T') ? rec.savedAt.split('T').first : rec.savedAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.04),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.12)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              playing ? Icons.stop_circle : Icons.play_circle_fill,
              color: theme.colorScheme.primary,
              size: 32,
            ),
            onPressed: () => _togglePlay(rec),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rec.name,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$date · $sizeMb MB',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            onPressed: () => _deleteRecording(rec),
          ),
        ],
      ),
    );
  }

  // Cloud recording: enable toggle + S3 destination fields.
  Widget _buildCloudCard() {
    return AppleSectionCard(
      title: 'Cloud Recording (S3)',
      subtitle: 'Save the full session video to your own AWS S3 bucket',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            CustomToggle(
              label: 'Enable Recording',
              description: 'Record the session and upload it to S3',
              checked: _enableRecording,
              onChanged: (val) => setState(() => _enableRecording = val),
            ),
            if (_enableRecording) ...[
              const SizedBox(height: 8),
              _buildResponsiveInputRow(
                context,
                [
                  Expanded(
                    child: CustomInputField(
                      label: 'Bucket Name',
                      placeholder: 'my-talbotiq-bucket',
                      controller: _bucketController,
                    ),
                  ),
                  Expanded(
                    child: CustomInputField(
                      label: 'Region',
                      placeholder: 'us-east-1',
                      controller: _regionController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CustomInputField(
                label: 'AWS Assume Role ARN',
                placeholder: 'arn:aws:iam::xxxxxxxxxxxx:role/TavusRole',
                controller: _roleArnController,
              ),
            ],
        ],
      ),
    );
  }

  // On-device recording library: toggle + playable/deletable list.
  Widget _buildLocalCard(AppStore store) {
    final theme = Theme.of(context);
    return AppleSectionCard(
      title: 'Interview Recordings',
      subtitle: 'Audio recordings are stored only on this device.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Save interview recordings'),
              subtitle: Text(
                'Keep a local .wav of each interview to play back here.',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
              ),
              value: store.storeLocalRecordings,
              onChanged: (v) => store.setStoreLocalRecordings(v),
            ),
            Divider(color: theme.colorScheme.outline.withOpacity(0.12)),
            const SizedBox(height: 8),
            if (store.recordings.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  store.storeLocalRecordings
                      ? 'No recordings yet — finish an interview to save one.'
                      : 'Enable saving above to keep recordings of your interviews.',
                  style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                ),
              )
            else
              ...store.recordings.map(_buildRecordingRow),
        ],
      ),
    );
  }

  // Lays children in a row on wide screens, stacked column on mobile.
  Widget _buildResponsiveInputRow(BuildContext context, List<Widget> children) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children.map((child) {
          Widget unwrapped = child;
          if (child is Expanded) {
            unwrapped = child.child;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: unwrapped,
          );
        }).toList(),
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children.map((child) {
          if (child is Expanded) return child;
          return Expanded(child: child);
        }).toList().expand((child) => [child, const SizedBox(width: 16)]).toList()..removeLast(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = Provider.of<AppStore>(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCloudCard(),
        const SizedBox(height: 24),
        CustomButton(text: 'Save Recording Settings', onPressed: _saveCloud),
        const SizedBox(height: 16),
        _buildLocalCard(store),
      ],
    );
  }
}
