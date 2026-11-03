# Briska Versioning

Current version: `1.0.0+2`

- User-facing version: `1.0.0`
- Android versionCode: `2`
- Flutter build name: `1.0.0`
- Flutter build number: `2`

Future beta builds can increment only the build number when the public version remains the same:

```yaml
version: 1.0.0+2
```

For a visible app version update:

```yaml
version: 1.0.1+3
```

The About screen reads the version and build dynamically from the installed app package.
