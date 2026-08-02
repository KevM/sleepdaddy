/**
 * main.js
 * SleepDaddy site-wide UI interactions, TestFlight fallback handling,
 * smooth scrolling, and accordion toggle accessibility.
 */

document.addEventListener('DOMContentLoaded', () => {
  // 1. Visibly degraded TestFlight CTA handling when URL is unset
  const testflightBtns = document.querySelectorAll('.btn-testflight, a[href*="TESTFLIGHT_URL"], a[href$="#download"]');
  testflightBtns.forEach(btn => {
    const rawHref = btn.getAttribute('href') || '';
    // If build-time sed did not replace placeholder or if set to generic fallback
    if (rawHref === 'TESTFLIGHT_URL' || rawHref === '#download' || rawHref === 'index.html#download' || rawHref.endsWith('#download')) {
      // Check if button is the primary download card action on index page
      const isHomeDownloadBox = btn.closest('.hero-cta-group') || btn.closest('.download-card') || btn.closest('.cta-box');
      if (!isHomeDownloadBox) {
        btn.textContent = 'TestFlight Beta Coming Soon';
        btn.classList.add('btn-disabled');
        btn.removeAttribute('target');
        btn.setAttribute('aria-disabled', 'true');
        btn.addEventListener('click', (e) => {
          e.preventDefault();
        });
      }
    }
  });

  // 2. Smooth Scroll for internal anchor links
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
      const targetId = this.getAttribute('href');
      if (targetId && targetId !== '#') {
        const targetEl = document.querySelector(targetId);
        if (targetEl) {
          e.preventDefault();
          targetEl.scrollIntoView({ behavior: 'smooth' });
        }
      }
    });
  });
});
