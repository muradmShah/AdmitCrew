"""Password hashing for the local/backend-managed student account flow."""
import hashlib
import hmac
import re
import secrets

def email_address(value):
    value=value.strip().casefold()
    if len(value)>254 or not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+',value):
        raise ValueError('Enter a valid email address.')
    return value

def hash_password(password):
    if not 10<=len(password)<=128: raise ValueError('Use a password with 10–128 characters.')
    salt=secrets.token_hex(16)
    digest=hashlib.pbkdf2_hmac('sha256',password.encode(),bytes.fromhex(salt),600000).hex()
    return f'pbkdf2_sha256$600000${salt}${digest}'

def verify_password(password,encoded):
    try:
        algorithm,iterations,salt,expected=encoded.split('$')
        if algorithm!='pbkdf2_sha256': return False
        actual=hashlib.pbkdf2_hmac('sha256',password.encode(),bytes.fromhex(salt),int(iterations)).hex()
        return hmac.compare_digest(actual,expected)
    except (ValueError,TypeError): return False

DUMMY_HASH=hash_password('unused-comparison-password')
