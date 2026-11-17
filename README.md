<img src="assets/icon.svg" width="64" height="64" alt="">

# Vim Dialogue

Vim keys for dialogue in World of Warcraft: Forever. Talk to an NPC, move through the list, and answer without the mouse.

On the window in the screenshot, the quest is already highlighted. Space or Enter takes it. Esc says goodbye.

```
j  l  down     next row
k  h  up       previous row
space  enter   confirm
esc            goodbye, decline, or cancel
```

Arrows do the same as hjkl. A single option is already selected, so Space takes it. With several quests or gossip lines, j and k move the gold bar. h and l move too, which matters more on a reward row or a book than on a tall list.

The open window lists every key along its bottom edge. The words follow the window: a gossip line says select and goodbye, a quest offer says accept and decline, a turn-in says complete and cancel, and a book says next page and close. If the window is already against the bottom of the screen, the list sits above it.

The same keys cover the whole conversation:

| Window | Space or Enter | Esc |
|---|---|---|
| Gossip, or a quest greeting | The highlighted quest or line | Goodbye |
| Quest offer | Accept | Decline |
| Quest progress | Continue | Cancel |
| Turn-in | Complete. j and k pick a reward first | Cancel |
| Book or letter | Next page, then close | Close |

A yes or no popup in front of the window takes the keys. Space confirms it. Esc cancels it.

The keys are borrowed only while a dialogue window is open. Jump, chat, and the quest log keep their keys the rest of the time. Typing in a box keeps the keys too.

`/vimdialogue` or `/vd` turns it on or off. `on`, `off`, and `help` work after either command.

## Install

The addon is the `VimDialogue` folder. Copy or symlink it into:

`World of Warcraft/_forever_/Interface/AddOns/VimDialogue`

It loads on Forever (interface **16001**). If the addon list marks it out of date after a patch, check the live interface with `/dump select(4, GetBuildInfo())` and put that number in `## Interface` in `VimDialogue.toc`.

These keys drive Blizzard's dialogue window. A skin that only repaints that window is fine. An addon that replaces the window with its own is outside this one.

If a dialogue window closes while you are in combat, the game will not give the keys back until combat ends. Pressing them in that gap does nothing.

## License

[MIT](LICENSE).
