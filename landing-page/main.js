/* ==========================================================================
   DOKA CAM LANDING PAGE INTERACTIVE SCRIPT
   Features: Before/After Slider, Mobile Menu, FAQ Accordion, Reveal Animation
   ========================================================================== */

document.addEventListener('DOMContentLoaded', () => {

    // --- 1. Mobile Menu Toggle ---
    const menuToggle = document.getElementById('menu-toggle');
    const navMenu = document.getElementById('nav-menu');
    const navLinks = document.querySelectorAll('.nav-link');

    if (menuToggle && navMenu) {
        menuToggle.addEventListener('click', () => {
            menuToggle.classList.toggle('active');
            navMenu.classList.toggle('active');
            
            // Toggle hamburger icon animation
            const spans = menuToggle.querySelectorAll('span');
            if (menuToggle.classList.contains('active')) {
                spans[0].style.transform = 'rotate(45deg) translate(6px, 6px)';
                spans[1].style.opacity = '0';
                spans[2].style.transform = 'rotate(-45deg) translate(5px, -5px)';
            } else {
                spans[0].style.transform = 'none';
                spans[1].style.opacity = '1';
                spans[2].style.transform = 'none';
            }
        });

        // Close menu when clicking a link
        navLinks.forEach(link => {
            link.addEventListener('click', () => {
                menuToggle.classList.remove('active');
                navMenu.classList.remove('active');
                const spans = menuToggle.querySelectorAll('span');
                spans.forEach(span => span.style.transform = 'none');
                spans[1].style.opacity = '1';
            });
        });
    }

    // --- 2. Interactive Before/After Slider ---
    const sliderContainer = document.querySelector('.slider-container');
    const imgAfter = document.querySelector('.image-after');
    const sliderHandle = document.getElementById('slider-handle');

    if (sliderContainer && imgAfter && sliderHandle) {
        let isDragging = false;

        const updateSlider = (clientX) => {
            const rect = sliderContainer.getBoundingClientRect();
            const x = clientX - rect.left;
            let percentage = (x / rect.width) * 100;
            
            // Clamp percentage between 0 and 100
            percentage = Math.max(0, Math.min(100, percentage));
            
            // Update widths & position
            imgAfter.style.width = `${percentage}%`;
            sliderHandle.style.left = `${percentage}%`;
        };

        // Mouse Events
        sliderHandle.addEventListener('mousedown', () => {
            isDragging = true;
            sliderContainer.classList.add('dragging');
        });

        window.addEventListener('mousemove', (e) => {
            if (!isDragging) return;
            updateSlider(e.clientX);
        });

        window.addEventListener('mouseup', () => {
            if (isDragging) {
                isDragging = false;
                sliderContainer.classList.remove('dragging');
            }
        });

        // Touch Events (Mobile)
        sliderHandle.addEventListener('touchstart', () => {
            isDragging = true;
        });

        window.addEventListener('touchmove', (e) => {
            if (!isDragging) return;
            updateSlider(e.touches[0].clientX);
        });

        window.addEventListener('touchend', () => {
            isDragging = false;
        });

        // Double click/Tap to center slider
        sliderContainer.addEventListener('dblclick', () => {
            imgAfter.style.transition = 'width 0.3s ease';
            sliderHandle.style.transition = 'left 0.3s ease';
            
            imgAfter.style.width = '50%';
            sliderHandle.style.left = '50%';
            
            setTimeout(() => {
                imgAfter.style.transition = 'none';
                sliderHandle.style.transition = 'none';
            }, 300);
        });
    }

    // --- 3. FAQ Accordion ---
    const accordionItems = document.querySelectorAll('.accordion-item');

    accordionItems.forEach(item => {
        const header = item.querySelector('.accordion-header');
        
        if (header) {
            header.addEventListener('click', () => {
                const isActive = item.classList.contains('active');
                
                // Close all accordion items
                accordionItems.forEach(otherItem => {
                    otherItem.classList.remove('active');
                });
                
                // Toggle clicked item
                if (!isActive) {
                    item.classList.add('active');
                }
            });
        }
    });

    // --- 4. Micro-animations: Scroll Reveal ---
    // Injecting CSS styles for scroll reveal animation
    const style = document.createElement('style');
    style.innerHTML = `
        .reveal-element {
            opacity: 0;
            transform: translateY(30px);
            transition: opacity 0.8s cubic-bezier(0.16, 1, 0.3, 1), transform 0.8s cubic-bezier(0.16, 1, 0.3, 1);
        }
        .reveal-element.revealed {
            opacity: 1;
            transform: translateY(0);
        }
    `;
    document.head.appendChild(style);

    const revealElements = document.querySelectorAll('.feature-card, .section-header, .slider-wrapper, .pricing-card, .accordion-item');
    
    // Set up Intersection Observer for scroll reveal
    const observerOptions = {
        root: null,
        rootMargin: '0px',
        threshold: 0.12
    };

    const observer = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('revealed');
                observer.unobserve(entry.target); // Stop observing once animated
            }
        });
    }, observerOptions);

    // Initialize elements and observe them
    revealElements.forEach(el => {
        el.classList.add('reveal-element');
        observer.observe(el);
    });
});
