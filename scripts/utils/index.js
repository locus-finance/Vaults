module.exports = {
    getEnv(name) {
        const value = process.env[name];
        if (!value) {
            throw new Error(`Missing environment variable ${name}`);
        }
        return value;
    },
};
