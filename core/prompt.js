/**
 * core/prompt.js
 * Terminal prompt helpers with color and validation
 */

const readline = require('readline');

// ── Colors ──────────────────────────────────────────────────────────────────
const C = {
  reset:   '\x1b[0m',
  red:     '\x1b[31m',
  green:   '\x1b[32m',
  yellow:  '\x1b[33m',
  blue:    '\x1b[34m',
  magenta: '\x1b[35m',
  cyan:    '\x1b[36m',
  white:   '\x1b[37m',
  bold:    '\x1b[1m',
  dim:     '\x1b[2m'
};

const c = (color, text) => `${C[color]}${text}${C.reset}`;

// ── RL Interface ─────────────────────────────────────────────────────────────
let rl = null;

function getRL() {
  if (!rl) {
    rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });
  }
  return rl;
}

function closeRL() {
  if (rl) {
    rl.close();
    rl = null;
  }
}

// ── Ask ──────────────────────────────────────────────────────────────────────
function ask(question) {
  return new Promise(resolve => {
    getRL().question(question, answer => resolve(answer.trim()));
  });
}

// ── Prompt with default ───────────────────────────────────────────────────────
async function prompt(label, defaultVal = '', { secret = false } = {}) {
  const def = defaultVal ? c('dim', ` [${secret ? '••••••••' : defaultVal}]`) : '';
  const line = `  ${c('cyan', '➜')} ${label}${def}: `;

  if (secret) {
    // Mask input on supported terminals
    const answer = await ask(line);
    return answer || defaultVal;
  }

  const answer = await ask(line);
  return answer || defaultVal;
}

// ── Confirm ──────────────────────────────────────────────────────────────────
async function confirm(label, defaultYes = true) {
  const hint = defaultYes ? 'Y/n' : 'y/N';
  const answer = await ask(`  ${c('cyan', '➜')} ${label} ${c('dim', `[${hint}]`)}: `);
  if (!answer) return defaultYes;
  return answer.toLowerCase().startsWith('y');
}

// ── Select ───────────────────────────────────────────────────────────────────
async function select(label, options, defaultIndex = 0) {
  console.log(`\n  ${c('yellow', label)}`);
  options.forEach((opt, i) => {
    const marker = i === defaultIndex ? c('green', '▶') : ' ';
    console.log(`  ${marker} ${c('dim', `[${i + 1}]`)} ${opt.label}`);
    if (opt.desc) console.log(`       ${c('dim', opt.desc)}`);
  });
  console.log('');

  while (true) {
    const answer = await ask(`  ${c('cyan', '➜')} Enter choice ${c('dim', `[${defaultIndex + 1}]`)}: `);
    const num = parseInt(answer || String(defaultIndex + 1));
    if (num >= 1 && num <= options.length) return options[num - 1];
    log.error(`Please enter a number between 1 and ${options.length}`);
  }
}

// ── Validated prompt ──────────────────────────────────────────────────────────
async function promptValidated(label, validator, defaultVal = '', opts = {}) {
  while (true) {
    const answer = await prompt(label, defaultVal, opts);
    const result = validator(answer);
    if (result === true) return answer;
    log.error(typeof result === 'string' ? result : 'Invalid input, please try again');
  }
}

// ── Log helpers ───────────────────────────────────────────────────────────────
const log = {
  section(title, color = 'magenta') {
    const line = '═'.repeat(76);
    console.log('');
    console.log(c(color, `╔${line}╗`));
    console.log(c(color, `║  ${title.padEnd(74)}║`));
    console.log(c(color, `╚${line}╝`));
    console.log('');
  },
  info(label, value = '') {
    if (value) {
      console.log(`  ${c('cyan', '➜')} ${label}: ${c('green', value)}`);
    } else {
      console.log(`  ${c('dim', '·')} ${label}`);
    }
  },
  success(msg) { console.log(`  ${c('green', '✅')} ${msg}`); },
  error(msg)   { console.log(`  ${c('red', '❌')} ${msg}`); },
  warn(msg)    { console.log(`  ${c('yellow', '⚠️ ')} ${msg}`); },
  tx(hash, explorer = '') {
    console.log(`  ${c('green', '✅')} TX: ${c('cyan', hash)}`);
    if (explorer) console.log(`     ${c('dim', `${explorer}/tx/${hash}`)}`);
  },
  step(n, total, msg) {
    console.log(`\n  ${c('yellow', `[${n}/${total}]`)} ${msg}`);
  }
};

module.exports = { prompt, promptValidated, confirm, select, ask, log, closeRL, c, C };
