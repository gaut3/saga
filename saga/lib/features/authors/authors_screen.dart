import 'package:flutter/material.dart';

import '../../shared/widgets/saga_error_view.dart';
import '../../core/theme/saga_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/models/plex_author.dart';
import '../../core/plex/plex_client.dart';
import '../../core/providers.dart';
import '../../shared/widgets/book_card.dart';

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
    // Token in a header, not the URL — same rule as BookCoverImage.
    // Image.network checks Flutter's ImageCache synchronously — cache hits never
    // show the placeholder at all (frameBuilder.wasSynchronouslyLoaded = true).
    final thumbUri = PlexClient.instance.buildThumbUrl(author.thumbPath);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: 48,
          height: 48,
          child: thumbUri != null
              ? Image.network(
                  thumbUri,
                  headers: PlexClient.instance.authHeaders,
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
    // Pushed on a tab stack — rebuilds come from nowhere else on a theme
    // switch, so watch it here.
    ref.watch(sagaThemeVariantProvider);
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
          // Pushed onto the tab navigator, so the nav pill and mini player
          // paint over the bottom of this list — pad past them.
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
          // No author line: every book here has the same author and the app
          // bar already says who.
          gridDelegate: bookGridDelegate(showAuthor: false),
          itemCount: books.length,
          itemBuilder: (context, i) =>
              BookCard(book: books[i], showAuthor: false),
        ),
      ),
    );
  }
}
