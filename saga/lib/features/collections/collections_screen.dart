import 'package:flutter/material.dart';

import '../../shared/widgets/saga_error_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../shared/widgets/book_cover_image.dart';
import '../../core/storage/custom_collection_store.dart';
import '../../core/theme/saga_theme.dart';
import 'collection_detail_screen.dart';
import '../../shared/widgets/saga_sheet.dart';

class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sagaThemeVariantProvider);
    final libraryKeyAsync = ref.watch(activeLibraryKeyProvider);

    return Scaffold(
      backgroundColor: SagaColors.bg,
      body: libraryKeyAsync.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: SagaColors.accent)),
        error: (e, _) => SagaErrorView(
          message: 'Could not load your library',
          error: e,
          onRetry: () => ref.invalidate(activeLibraryKeyProvider),
        ),
        data: (key) {
          if (key == null) {
            return Center(
              child: Text('No library found',
                  style: TextStyle(color: SagaColors.fgMuted)),
            );
          }
          return _CollectionsContent(libraryKey: key);
        },
      ),
    );
  }
}

class _CollectionsContent extends ConsumerWidget {
  final String libraryKey;
  const _CollectionsContent({required this.libraryKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(customCollectionsProvider);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: Colors.transparent,
          foregroundColor: SagaColors.fg,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [SagaColors.bg, SagaColors.bg.withValues(alpha: 0.0)],
                stops: const [0.6, 1.0],
              ),
            ),
          ),
          title: const Text('Collections',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'New collection',
              onPressed: () => _showCreateDialog(context, ref),
            ),
          ],
        ),
        if (collections.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_outlined,
                      size: 56, color: SagaColors.fgSubtle),
                  const SizedBox(height: 16),
                  Text('No collections yet',
                      style:
                          TextStyle(color: SagaColors.fgSubtle, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('Tap + to create one',
                      style:
                          TextStyle(color: SagaColors.fgSubtle, fontSize: 13)),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.1,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _CollectionTile(
                  collection: collections[i],
                  libraryKey: libraryKey,
                  onDelete: () => _deleteCollection(context, ref, collections[i]),
                  onRename: () => _showRenameDialog(context, ref, collections[i]),
                ),
                childCount: collections.length,
              ),
            ),
          ),
      ],
    );
  }

  /// One dialog for naming a collection, whichever way it's reached — create
  /// and rename were ~35 identical lines differing only in title, button and
  /// initial text, and had nowhere to drift but apart.
  Future<String?> _promptCollectionName(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    String? initial,
  }) async {
    final controller = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SagaColors.surface,
        title: Text(title, style: TextStyle(color: SagaColors.fg)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: SagaColors.fg),
          decoration: InputDecoration(
            hintText: 'Collection name',
            hintStyle: TextStyle(color: SagaColors.fgSubtle),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: SagaColors.fgMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child:
                Text(confirmLabel, style: TextStyle(color: SagaColors.accent)),
          ),
        ],
      ),
    );
    // The dialog is gone by the time this future completes, so the controller
    // has no listeners left and nothing further needs it. Dispose is the
    // contract for anything that can be listened to; every dialog-scoped
    // controller in the app is released on this same line.
    controller.dispose();
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final name = await _promptCollectionName(context,
        title: 'New collection', confirmLabel: 'Create');
    if (name != null) {
      await CustomCollectionStore.create(name);
      ref.read(customCollectionRevisionProvider.notifier).state++;
    }
  }

  Future<void> _showRenameDialog(
      BuildContext context, WidgetRef ref, CustomCollection col) async {
    final name = await _promptCollectionName(context,
        title: 'Rename', confirmLabel: 'Save', initial: col.name);
    if (name != null) {
      await CustomCollectionStore.rename(col.id, name);
      ref.read(customCollectionRevisionProvider.notifier).state++;
    }
  }

  Future<void> _deleteCollection(
      BuildContext context, WidgetRef ref, CustomCollection col) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SagaColors.surface,
        title: Text('Delete "${col.name}"?',
            style: TextStyle(color: SagaColors.fg)),
        content: Text('This will remove the collection but not your books.',
            style: TextStyle(color: SagaColors.fgMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: SagaColors.fgMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await CustomCollectionStore.delete(col.id);
      ref.read(customCollectionRevisionProvider.notifier).state++;
    }
  }
}

class _CollectionTile extends StatelessWidget {
  final CustomCollection collection;
  final String libraryKey;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  const _CollectionTile({
    required this.collection,
    required this.libraryKey,
    required this.onDelete,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CollectionDetailScreen(
            collection: collection,
            libraryKey: libraryKey,
          ),
        ),
      ),
      onLongPress: () => _showOptions(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Cover image or placeholder
            if (collection.thumbPath != null)
              // Tile is 1.1:1 — letterbox so square covers keep their top and
              // bottom. cacheWidth matches the ~half-screen tile.
              BookCoverImage(
                  thumbPath: collection.thumbPath,
                  cacheWidth: kCoverCacheWidthDetail,
                  letterboxed: true)
            else
              _coverPlaceholder(),
            // Gradient + text overlay at the bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 20, 10, 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      collection.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${collection.bookRatingKeys.length} '
                      '${collection.bookRatingKeys.length == 1 ? 'book' : 'books'}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder() => Container(
        color: SagaColors.surface,
        child: Center(
          child: Icon(Icons.folder_rounded, color: SagaColors.accent, size: 40),
        ),
      );

  void _showOptions(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    showSagaSheet(context, (_) => Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit_outlined, color: SagaColors.fg),
              title:
                  Text('Rename', style: TextStyle(color: SagaColors.fg)),
              onTap: () {
                Navigator.pop(context);
                onRename();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
          ],
        ),
      ), scrollable: false);
  }
}
