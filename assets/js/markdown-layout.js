// Markdown Layout System для статичен GitHub Pages
document.addEventListener('DOMContentLoaded', function() {
    // Проверява дали страницата е Markdown (.md)
    const isMarkdownPage = document.body.textContent.includes('<!DOCTYPE html>') === false ||
                          window.location.pathname.endsWith('.md') ||
                          document.querySelector('meta[name="generator"][content*="markdown"]');

    if (isMarkdownPage) {
        applyMarkdownLayout();
    }
});

function applyMarkdownLayout() {
    // Създава header
    const header = document.createElement('header');
    header.className = 'markdown-header';
    header.innerHTML = `
        <div class="container">
            <h1><i class="fas fa-cube"></i> K3s-Odoo Документация</h1>
            <nav class="breadcrumb-nav">
                <a href="/">🏠 Начало</a>
                <span class="separator">→</span>
                <span class="current">${getPageTitle()}</span>
            </nav>
        </div>
    `;

    // Създава wrapper за съдържанието
    const wrapper = document.createElement('div');
    wrapper.className = 'markdown-content';

    // Пренася съществуващото съдържание
    const bodyContent = document.body.innerHTML;
    wrapper.innerHTML = bodyContent;

    // Създава footer
    const footer = document.createElement('footer');
    footer.className = 'markdown-footer';
    footer.innerHTML = `
        <div class="container">
            <p>&copy; 2024 K3s-Odoo Enterprise Platform. Designed for Production Excellence.</p>
            <p>
                <i class="fas fa-envelope"></i> Enterprise Support:
                <a href="mailto:vladimirov.rosen@gmail.com">vladimirov.rosen@gmail.com</a>
            </p>
        </div>
    `;

    // Изчиства body и добавя новата структура
    document.body.innerHTML = '';
    document.body.appendChild(header);
    document.body.appendChild(wrapper);
    document.body.appendChild(footer);

    // Добавя CSS стиловете
    loadMarkdownCSS();
}

function getPageTitle() {
    // Извлича заглавие от URL или първия H1
    const h1 = document.querySelector('h1');
    if (h1) return h1.textContent.replace(/[^\w\s-]/g, '').trim();

    const path = window.location.pathname;
    return path.split('/').pop().replace('.md', '').replace('-', ' ');
}

function loadMarkdownCSS() {
    // Проверява дали CSS е вече зареден
    if (document.querySelector('link[href*="style.css"]')) return;

    const cssLink = document.createElement('link');
    cssLink.rel = 'stylesheet';
    cssLink.href = '/style.css'; // Absolute path
    document.head.appendChild(cssLink);

    // Добавя Font Awesome
    const faLink = document.createElement('link');
    faLink.rel = 'stylesheet';
    faLink.href = 'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css';
    document.head.appendChild(faLink);

    // Добавя Google Fonts
    const googleFonts = document.createElement('link');
    googleFonts.rel = 'stylesheet';
    googleFonts.href = 'https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap';
    document.head.appendChild(googleFonts);
}