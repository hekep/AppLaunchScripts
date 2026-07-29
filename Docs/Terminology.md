# Terminology

## Display

A physical or virtual monitor recognized by macOS.

Examples include a built-in MacBook display, an external monitor, or a virtual Visor display.

## Space

A macOS virtual desktop associated with a Display.

When "Displays have separate Spaces" is enabled, each Display has its own ordered collection of Spaces.

## Workspace

A named, declarative configuration containing applications, a target Display and Space, and a window layout.

A Workspace is an AppLaunchScripts concept. It is not a native macOS Space name.

## Layout

A description of where windows go on the screen. Named layouts are unit rects (`leftHalf`, `right34`, `center`, …); workspace layouts split the screen horizontally or vertically by percentages. See the [API](API.md) for the full list and the dynamic `left<N>`/`right<N>`/`top<N>`/`bottom<N>` forms.
