> [!NOTE]
> **Performance fork** of [loneka/avalog](https://github.com/loneka/avalog) 0.1.13. Same features and look,
> but switching categories (Body, Clothing, ...) no longer freezes the game:
>
> - Item buttons are pooled and reused: a category switch relabels existing buttons instead of rebuilding them.
>   New buttons are built within a small time budget per frame. Category and sub-category tabs are reused the same way.
> - Each button's Buy/details row is only built once that item is equipped.
> - A category click runs one catalog search instead of several, late results from an old search are ignored,
>   and finished searches are cached for the session, so going back to a category is instant.
> - Page loads no longer overlap when scrolling, and failed searches are retried next time.
> - The avatar preview and the clock stop updating while the menu is closed.
>
> Measured in a Studio playtest: Body click 67 ms → 24 ms blocked, worst frame after switching 133–290 ms → about 30 ms.

<p align="center">
  <a href="https://loneka.com/avalog">
    <picture>
      <source srcset="/gh-assets/LogoStamp.svg"></source>
      <img alt="Avalog" src="/gh-assets/LogoStamp.svg" height="80"></img>
    </picture>
  </a>
</p>

<p align="center">
  Easy, themable avatar catalog for Roblox
</p>

<p align="center">
  <a href="https://avafe.me/"><img src="https://img.shields.io/badge/avafe.me-%239f84ff?style=for-the-badge&logo=inertia&logoColor=white " /></a>
  <a href="https://avafe.me/bsky"><img src="https://img.shields.io/badge/Bluesky-0285FF?logo=bluesky&logoColor=fff&style=for-the-badge" /></a>
  <a href="https://avafe.me/x"><img src="https://img.shields.io/badge/X-000000?style=for-the-badge&logo=x&logoColor=white" /></a>
  <a href="https://avafe.me/discord"><img src="https://img.shields.io/badge/Discord-5865F2?style=for-the-badge&logo=discord&logoColor=white"></img></a>
</p>

---

## Demo 📽️

https://github.com/user-attachments/assets/4f278391-142b-46b9-bed0-8018e638d70c

[Or try it out in-game! 🎮](https://www.roblox.com/games/95426183703947)

## Simplicity 😌

Avalog prioritizes your experience, and doesn't bombard you with branding, sign-up, or clunk.

## Customization 🖌️

Comprehensive theming properties allow you to match your game's mood and style with ease.

## Monetization 💸

Earn 40% on all items sold in your game, and list your own UGC items.

## [Documentation 📄](https://loneka.com/avalog/)

##

<span align="center">
  <a href="https://suite.loneka.com" target="_blank" rel="noopener noreferrer"><img src="https://github.com/user-attachments/assets/05d870f1-a166-4908-a437-a62b27be4bec" height="120px"></img></a>
  <a href="https://avafe.me" target="_blank" rel="noopener noreferrer"><img src="https://github.com/user-attachments/assets/7e8ca32f-d08d-48d7-b9a1-0146092d555b" height="120px"></img></a>
</span>
