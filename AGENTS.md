# PS2 implementation rules

Follow `docs/assignment.md` and the command/record contracts in
`docs/INTERFACES.md`. The application lives under `book-manager/`.

- Keep the prescribed layers and primarily small Bash 3.2-compatible programs.
- Only `book-manager/data/book_database.sh` may access the personal `books.csv`.
- Components emit JSON Lines on stdout; progress/errors go on stderr.
- Personalization is leisure literature: novels, short stories, mystery,
  fantasy, travel writing, and essays. Do not substitute professional reading.
- The personal library starts empty. Clearly label isolated demo data.
- Preserve verified bibliographic source links; never invent book metadata.
- Use isolated data directories for validation; avoid altering the real library.
- Delegate independent execution modules to `gpt-6-luna`; the root agent owns
  interfaces, integration, and final verification.
