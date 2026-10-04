# Privacy

The check-usage skill runs entirely on your machine.

- **What it reads.** It runs Claude Code's own `/usage` command and reads the usage cache
  that Claude Code keeps in its own configuration file in your home directory. From that file it uses
  only usage percentages, reset times, plan tier and usage-credit status. It never prints your
  name, email address, account or organisation identifiers.
- **What it sends.** Nothing. The skill makes no network requests of its own. The only network
  call is the one Claude Code itself makes when `/usage` runs.
- **What it stores.** Nothing. The skill writes no files and keeps no data between runs.

Questions: open an issue on the project's GitHub repository.
