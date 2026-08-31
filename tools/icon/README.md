# App icon

`Tenuo.icon` is the source for the app icon. `export.sh` renders the source and
writes the checked-in bundle resources and app artwork.

Run it from the repository root:

```sh
./tools/icon/export.sh
```

The script requires Xcode's `actool` and Swift. Review generated changes before
committing them. Preview output is intentionally ignored.
