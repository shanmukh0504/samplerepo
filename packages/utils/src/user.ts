export interface Utils {
    addr: string;
    exp: number;
}

export const createUser = (addr: string, exp: number): Utils => ({ addr, exp });

export const showUser = (user: Utils) => console.log(`User ${user.addr} at ${user.exp} seconds.`);