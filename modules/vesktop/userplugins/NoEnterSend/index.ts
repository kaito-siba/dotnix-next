/*
 * Vencord, a Discord client mod
 * Copyright (c) 2023 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

// Inspired by https://github.com/Vendicated/Vencord/blob/b8dc0ae720e25d64f73eb9998c1f6c4e4f13f349/src/plugins/ctrlEnterSend/index.ts

import { definePluginSettings } from "@api/Settings";
import { Devs, IS_MAC } from "@utils/constants";
import definePlugin, { OptionType, PluginAuthor } from "@utils/types";

const customAuthors: PluginAuthor[] = [
    { name: "Nin", id: 1286362631984255162n }
];

let keydownListener: (e: KeyboardEvent) => void;

export default definePlugin({
    name: "NoEnterSend",
    authors: customAuthors,
    description: "Customizable Enter key behavior. (Note: To send inside an open code block, enable 'Show Send Message Button' in Discord's App Settings > Chat Box)",
    tags: ["Shortcuts", "Chat"],
    settings: definePluginSettings({
        submitRule: {
            description: "The way to send a message",
            type: OptionType.SELECT,
            options: [
                { label: "Ctrl+Enter", value: "ctrl+enter" },
                { label: "Shift+Enter", value: "shift+enter" },
                { label: "Enter", value: "enter" }
            ],
            default: "shift+enter"
        }
    }),
    patches: [
        {
            // Forces Discord's native engine to require a modifier.
            find: "disableEnterToSubmit",
            replacement: {
                match: /(submit\s*:\s*\{[^}]*?disableEnterToSubmit\s*:)\s*[^,}]+(,?)/g,
                replace: "$1 !0$2"
            }
        }
    ],
    start() {
        keydownListener = (e: KeyboardEvent) => {
            if (e.key !== "Enter") return;

            // Ensure we are inside a text box
            const target = e.target as HTMLElement;
            if (!target || !target.closest('[class*="slateContainer"], [class*="textArea"], [role="textbox"]')) return;

            // Don't mutate if an Autocomplete menu (@mention, emoji) is open
            if (document.querySelector('[class*="autocomplete_"], [class*="autocompleteAttached_"]')) return;

            const rule = this.settings.store.submitRule;
            const isCtrl = IS_MAC ? e.metaKey : e.ctrlKey;
            const isShift = e.shiftKey;

            let forceSend = false;
            let forceNewline = false;

            if (rule === "shift+enter") {
                if (isShift) forceSend = true;
                else if (isCtrl) forceNewline = true;
            } else if (rule === "enter") {
                if (!isShift && !isCtrl) forceSend = true;
                else if (isCtrl) forceNewline = true;
            }

            if (forceSend) {
                // Mutate the event to pretend Ctrl+Enter was pressed. Discord will natively send.
                Object.defineProperty(e, IS_MAC ? 'metaKey' : 'ctrlKey', { get: () => true, configurable: true });
                Object.defineProperty(e, 'shiftKey', { get: () => false, configurable: true });
            } else if (forceNewline) {
                // Mutate the event to pretend bare Enter was pressed. Discord will natively newline.
                Object.defineProperty(e, IS_MAC ? 'metaKey' : 'ctrlKey', { get: () => false, configurable: true });
                Object.defineProperty(e, 'shiftKey', { get: () => false, configurable: true });
            }
        };

        // Attach to the document in the 'capture' phase so we mutate the event BEFORE React sees it.
        document.addEventListener("keydown", keydownListener, { capture: true });
    },
    stop() {
        if (keydownListener) {
            document.removeEventListener("keydown", keydownListener, { capture: true });
        }
    }
});
