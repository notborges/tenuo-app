# App icon

`Tenuo.icon` is the source for the app icon. `export.sh` renders the source and
writes the checked-in bundle resources and ignored preview images.

Run it from the repository root:

```sh
./tools/icon/export.sh
```

The script requires Xcode's `actool` and Swift. Review generated changes before
committing them. Preview output is intentionally ignored.

`TenuoPro.icon` is the optional graphite Dock icon. Export it with
`./tools/icon/export-pro.sh`. The app keeps the standard icon by default and
uses this variant only while running with Pro access and the preference enabled.
