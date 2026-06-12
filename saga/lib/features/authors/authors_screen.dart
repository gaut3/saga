import 'package:flutter/material.dart';

import '../../shared/widgets/saga_error_view.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/models/plex_author.dart';
import '../../core/plex/models/plex_book.dart';
import '../../core/plex/plex_client.dart';
import '../../core/providers.dart';
import '../library/book_detail_screen.dart';
import '../../shared/widgets/book_cover_image.dart';

class AuthorsScreen extends ConsumerWidget {
  const AuthorsScreen({super.key});

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
          return _AuthorsContent(libraryKey: key);
        },
      ),
    );
  }
}

class _AuthorsContent extends ConsumerWidget {
  final String libraryKey;
  const _AuthorsContent({required this.libraryKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authorsAsync = ref.watch(authorsProvider(libraryKey));

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
          title: Text('Authors',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        ),
        authorsAsync.when(
          loading: () => SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: SagaColors.accent),
              ),
            ),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: SagaErrorView(
              message: 'Could not load authors',
              error: e,
              onRetry: () => ref.invalidate(authorsProvider(libraryKey)),
            ),
          ),
          data: (authors) => SliverList(
            delegate: SliverChildListDelegate(
              authors.map((a) => _AuthorTile(author: a)).toList(),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 16)),
      ],
    );
  }
}

class _AuthorTile extends StatelessWidget {
  final PlexAuthor author;
  const _AuthorTile({required this.author});

  @override
  Widget build(BuildContext context) {
    // buildArtUri embeds the token in the URL so Image.network needs no headers.
    // Image.network checks Flutter's ImageCache synchronously — cache hits never
    // show the placeholder at all (frameBuilder.wasSynchronouslyLoaded = true).
    final thumbUri = PlexClient.instance.buildArtUri(author.thumbPath);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: 48,
          height: 48,
          child: thumbUri != null
              ? Image.network(
                  thumbUri.toString(),
                  fit: BoxFit.cover,
                  cacheWidth: 96,
                  cacheHeight: 96,
                  frameBuilder: (_, child, frame, syncLoad) {
                    if (syncLoad || frame != null) return child;
                    return _placeholder();
                  },
                  errorBuilder: (_, _, _) => _placeholder(),
                )
              : _placeholder(),
        ),
      ),
      title: Text(author.title,
          style: TextStyle(color: SagaColors.fg, fontSize: 15)),
      trailing: Icon(Icons.chevron_right, color: SagaColors.fgSubtle),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => _AuthorBooksScreen(author: author)),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: SagaColors.surface,
        child: Icon(Icons.person, color: SagaColors.fgSubtle, size: 28),
      );
}

class _AuthorBooksScreen extends ConsumerWidget {
  final PlexAuthor author;
  const _AuthorBooksScreen({required this.author});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksByAuthorProvider(author.ratingKey));

    return Scaffold(
      backgroundColor: SagaColors.bg,
      appBar: AppBar(
        backgroundColor: SagaColors.bg,
        foregroundColor: SagaColors.fg,
        title: Text(author.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: booksAsync.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: SagaColors.accent)),
        error: (e, _) => SagaErrorView(
          message: 'Could not load this author\'s books',
          error: e,
          onRetry: () => ref.invalidate(booksByAuthorProvider(author.ratingKey)),
        ),
        data: (books) => GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.62,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: books.length,
          itemBuilder: (context, i) => _BookTile(book: books[i]),
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  final PlexBook book;
  const _BookTile({required this.book});

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
              borderRadius: BorderRadius.circular(8),
              child: BookCoverImage(thumbPath: book.thumbPath),
            ),
          ),
          const SizedBox(height: 4),
          Text(book.title,
              style: TextStyle(color: SagaColors.fg, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

}
