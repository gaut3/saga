import 'package:flutter/material.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/models/plex_book.dart';
import '../../core/plex/models/plex_library.dart';
import '../../core/providers.dart';
import '../../shared/widgets/book_cover_image.dart';
import '../../shared/widgets/mini_player_bar.dart';
import 'book_detail_screen.dart';

class BooksScreen extends ConsumerWidget {
  final PlexLibrary library;

  const BooksScreen({super.key, required this.library});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider(library.key));

    return Scaffold(
      backgroundColor: SagaColors.bg,
      bottomNavigationBar: const MiniPlayerBar(),
      appBar: AppBar(
        title: Text(library.title),
        backgroundColor: SagaColors.surface,
        foregroundColor: SagaColors.fg,
      ),
      body: booksAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: SagaColors.accent),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text('$e',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SagaColors.fgMuted)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(booksProvider(library.key)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: SagaColors.accent),
                child: Text('Retry', style: TextStyle(color: SagaColors.accentFg)),
              ),
            ],
          ),
        ),
        data: (books) {
          if (books.isEmpty) {
            return Center(
              child: Text(
                'No audiobooks found in this library.',
                style: TextStyle(color: SagaColors.fgMuted),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.65,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: books.length,
            itemBuilder: (context, index) => _BookCard(book: books[index]),
          );
        },
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  final PlexBook book;

  const _BookCard({required this.book});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: BookCoverImage(thumbPath: book.thumbPath),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            style: TextStyle(
              color: SagaColors.fg,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (book.authorName != null)
            Text(
              book.authorName!,
              style: TextStyle(color: SagaColors.fgMuted, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

}
