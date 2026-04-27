import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../utils/toast_helper.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  bool _isSyncing = false;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPendingCount();
  }

  Future<void> _loadPendingCount() async {
    final pending = await DatabaseService.getPendingRecords();
    if (mounted) {
      setState(() {
        _pendingCount = pending.length;
      });
    }
  }

  Future<void> _startSync() async {
    final pending = await DatabaseService.getPendingRecords();
    if (pending.isEmpty) {
      if (mounted) showToast(context, 'No pending records to sync', type: ToastType.info);
      return;
    }

    setState(() => _isSyncing = true);

    try {
      final result = await ApiService.bulkSync(pending);
      if (result != null) {
        int successCount = 0;
        for (var res in result.results) {
          if (res.ok && res.localId != null) {
            await DatabaseService.markSynced(res.localId!);
            successCount++;
          } else if (res.localId != null && res.error != null) {
            await DatabaseService.updateSyncError(res.localId!, res.error!);
          }
        }

        if (mounted) {
          showToast(
            context,
            'Sync completed: $successCount successful, ${result.errors} errors',
            type: successCount > 0 ? ToastType.success : ToastType.error,
          );
        }
      } else {
        if (mounted) showToast(context, 'Sync failed: No response from server', type: ToastType.error);
      }
    } catch (e) {
      if (mounted) showToast(context, 'Sync error: $e', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
        _loadPendingCount();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Upload Attendance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF1B2D5B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFDBEAFE), width: 4),
              ),
              child: _isSyncing
                  ? const CircularProgressIndicator(color: Color(0xFF3B82F6))
                  : const Icon(Icons.cloud_upload_outlined, size: 64, color: Color(0xFF3B82F6)),
            ),
            const SizedBox(height: 32),
            Text(
              _isSyncing ? 'Syncing Records...' : 'Upload Records',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1B2D5B)),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _isSyncing
                    ? 'Please wait while we push your data to the server.'
                    : 'You have $_pendingCount locally saved attendance records ready to be synced to the server.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.5),
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: _isSyncing ? null : _startSync,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B2D5B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                disabledBackgroundColor: Colors.grey,
              ),
              child: Text(
                _isSyncing ? 'Syncing...' : 'Start Sync',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            if (!_isSyncing)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back', style: TextStyle(color: Color(0xFF64748B))),
              ),
          ],
        ),
      ),
    );
  }
}
