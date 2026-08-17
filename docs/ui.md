# Ashbloom UI

Ashbloom provides its own suite of tools that render UI passes with Vulkan. These tools are found in the following zig components:

- `utils/vkui.zig` - Where all of the basic UI components are defined.
- `utils/layouts.zig` - Contains some additional behavior protocols for placing new UI elements.
- `utils/ui_themes/basic.zig` - Contains the actual immediate-mode UI components.

You may be confused. How do `vkui.zig` and `basic.zig` both seem to contain the basic UI components? The answer is that these tools are essentially provided in two parts.

The first part, just `vkui.zig`, contain all of the foundational structures and behavior that most UI systems require. It defines the basic UI **element**, as well as a UI **container**, establishes behaviors for handling events (known as **callbacks**), etc. But, the `vkui.zig` module does not specify templates like buttons, sliders, text, textfields, etc, nor does it define any layouts. This is so that prospective developers can use this module and define their own element templates (a collection of these are known internally as a UI **theme**) to use for those basic objects.

The second part are those templates. These are provided as the "immediate-mode" theme found in `basic.zig`, as well as the layout behaviors found in `layouts.zig`. Before we describe those, however, it's good to understand what exactly an **element** is, and how this library is structured as a whole.
