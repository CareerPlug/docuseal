/**
 * Default Field Name Highlighting
 * 
 * This module provides utilities for detecting and highlighting fields with default names.
 * Default names follow the pattern "[Field Type] Field [Number]" (e.g., "Text Field 1", "Signature Field 2")
 * or "[Field Type] [Number]" for headings (e.g., "Heading 1", "Heading 2")
 */

/**
 * Regular expression to match default field names
 * Matches patterns like:
 * - "Text Field 1", "Text Field 2", etc.
 * - "Signature Field 1", "Signature Field 2", etc.
 * - "Heading 1", "Heading 2", etc.
 * - "Initials Field 1", "Initials Field 2", etc.
 * - "Date Field 1", "Date Field 2", etc.
 * - "Number Field 1", "Number Field 2", etc.
 * - "Image Field 1", "Image Field 2", etc.
 * - "File Field 1", "File Field 2", etc.
 * - "Select Field 1", "Select Field 2", etc.
 * - "Checkbox Field 1", "Checkbox Field 2", etc.
 * - "Multiple Field 1", "Multiple Field 2", etc.
 * - "Radio Field 1", "Radio Field 2", etc.
 * - "Cells Field 1", "Cells Field 2", etc.
 * - "Stamp Field 1", "Stamp Field 2", etc.
 * - "Payment Field 1", "Payment Field 2", etc.
 * - "Phone Field 1", "Phone Field 2", etc.
 * - "Verify ID Field 1", "Verify ID Field 2", etc.
 */
export const DEFAULT_FIELD_NAME_REGEX = /^(Text|Signature|Initials|Date|Number|Image|File|Select|Checkbox|Multiple|Radio|Cells|Stamp|Payment|Phone|Verify ID).*?\s+\d+$|^Heading\s+\d+$/i

/**
 * Check if a field name is a default name
 * @param {string} fieldName - The field name to check
 * @returns {boolean} True if the field name matches the default pattern
 */
export function isDefaultFieldName(fieldName) {
  if (!fieldName || typeof fieldName !== 'string' || fieldName.trim() === '') {
    return true
  }
  const isDefault = DEFAULT_FIELD_NAME_REGEX.test(fieldName)
  return isDefault
}

/**
 * Get the CSS classes for highlighting a default-named field
 * @returns {string} CSS classes for indigo highlighting
 */
export function getDefaultFieldHighlightClasses() {
  return '!border-indigo-500 !bg-indigo-100'
}

/**
 * Get the inline styles for highlighting a default-named field
 * @returns {Object} Inline styles for indigo highlighting
 */
export function getDefaultFieldHighlightStyles() {
  return {
    borderWidth: '3px',
    borderStyle: 'solid'
  }
}

/**
 * Get the tooltip message for default-named fields
 * @returns {string} Tooltip message explaining why the field is highlighted
 */
export function getDefaultFieldTooltipMessage() {
  return 'This field has a default name. Please rename it to something more descriptive for a better form filling experience.'
}

/**
 * Get the warning message for templates with default-named fields
 * @param {number} count - Number of fields with default names
 * @returns {string} Warning message
 */
export function getDefaultFieldWarningMessage(count) {
  if (count === 1) {
    return 'You have 1 field with a default name. Please rename it to something more descriptive for a better form filling experience.'
  }
  return `You have ${count} fields with default names. Please rename them to something more descriptive for a better form filling experience.`
}

/**
 * Count fields with default names
 * @param {Array} fields - Array of field objects
 * @returns {number} Count of fields with default names
 */
export function countDefaultFieldNames(fields) {
  if (!Array.isArray(fields)) {
    return 0
  }
  return fields.filter(field => isDefaultFieldName(field.name)).length
}

/**
 * Get all fields with default names
 * @param {Array} fields - Array of field objects
 * @returns {Array} Array of fields with default names
 */
export function getDefaultFieldNames(fields) {
  if (!Array.isArray(fields)) {
    return []
  }
  return fields.filter(field => isDefaultFieldName(field.name))
}
