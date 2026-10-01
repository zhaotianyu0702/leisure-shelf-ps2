# Short demo

The included silent terminal recording runs `./book-manager/app.sh --demo`.
Its reading states are examples, and it does not modify the personal library.
Record your own voice over the supplied footage, or record a new terminal video
following the same three operations. No generated narration is included.

1. **Browse and rate:** Open the example shelf, choose *Pride and Prejudice*, and
   show its reading state and rating.
2. **Add a book:** Look up *The Hobbit* by J.R.R. Tolkien, select the metadata
   match, choose want-to-read, and save it.
3. **Recommend and save:** Keep the leisure interests, watch the three programs
   run, inspect a recommendation's reason, and save it to the want-to-read shelf.

## Narration outline

Briefly explain these three points in your own words:

- The library is for leisure reading and tracks reading status and ratings.
  The demonstration uses a temporary example library.
- Adding a book starts with a metadata lookup. You confirm the title and author
  before saving it.
- Three recommendation strategies run concurrently. Their combined results
  pass through a pipe to remove duplicates and books already in the library,
  while retaining recommendation reasons. You can select a suggestion to save.
